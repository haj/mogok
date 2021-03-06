
module Bittorrent

  module Tracker
    include Passkey, BittorrentClient
    
    class TrackerFailure < StandardError
    end

    protected

      def process_scrape(params, config)
        logger.debug ':-) tracker.process_scrape'
        resp = ScrapeResponse.new
        begin
          failure 'not_allowed' unless config[:scrape_enabled]
          begin
            req = ScrapeRequest.new params
          rescue
            failure 'malformed_request'
          end

          set_torrent req, req.info_hashs[0] # only the first torrent is considered
          set_user req

          t = req.torrent
          resp.add_file(t.info_hash, t.seeders_count, t.leechers_count, t.snatches_count)          
        rescue TrackerFailure => e
          resp.failure_reason = i18n("process_scrape.#{e.message}")
        rescue => e
          log_error e
          resp.failure_reason = i18n('process_scrape.server_error')
        end
        resp.out(logger)
      end

      def process_announce(params, remote_ip, config)
        logger.debug ":-) tracker.process_announce: event = [#{params[:event]}]"
        resp = AnnounceResponse.new
        begin
          req = prepare_announce_req params, remote_ip, config

          process_announce_req req, config

          prepare_announce_resp req, resp, config
        rescue TrackerFailure => e
          resp.failure_reason = i18n("process_announce.#{e.message}")
        rescue => e
          log_error e
          resp.failure_reason = i18n('process_announce.server_error')
        end
        resp.out(logger)
      end

    private

      def failure(error_key)
        raise TrackerFailure.new(error_key)
      end

      def i18n(key)
        I18n.t("lib.bittorrent.tracker.#{key}")
      end

      def prepare_announce_req(req, remote_ip, config)
        begin
          req = AnnounceRequest.new params
        rescue
          failure 'malformed_request'
        end
        req.ip = remote_ip
        set_torrent req
        set_user req
        req.set_numwant config[:announce_resp_max_peers]
        req.client = parse_client req.peer_id, config[:ban_unknown_clients]

        check_announce_req_validity req
        req
      end

      def set_torrent(req, info_hash = nil)
        info_hash_hex = CryptUtils.hexencode(info_hash || req.info_hash)

        req.torrent = Torrent.find_by_info_hash_hex(info_hash_hex) # hex because memcached has problems with binary keys

        if req.torrent && req.torrent.active?
          logger.debug ":-) valid torrent: #{req.torrent.id} [#{req.torrent.name}]"
        else
          logger.debug ":-o torrent not found or inactive for info hash hex #{info_hash_hex}"
          failure 'invalid_torrent'          
        end
      end

      def set_user(req)
        id = parse_user_id_from_announce_passkey(req.passkey)
        if id
          req.user = User.find_by_id(id)
          if req.user && req.user.active?
            logger.debug ":-) valid user: #{req.user.id} [#{req.user.username}]"
            if req.passkey != make_announce_passkey(req.torrent, req.user)
              logger.debug ":-o invalid announce passkey: #{req.passkey}"
              failure 'invalid_passkey'              
            end
          else
            logger.debug ':-o user not found or inactive'
            failure 'invalid_user'            
          end
        else
          logger.debug ":-o unable to parse user id from announce passkey: #{req.passkey}"
          failure 'invalid_passkey'          
        end
        logger.debug ':-) valid announce passkey'
      end

      def check_announce_req_validity(req)
        case
          when !req.valid?
            failure 'invalid_request'
          when req.client.banned?
            failure 'client_banned'
          when req.client.banned_version?
            failure 'client_version_banned'
        end
      end

      def process_announce_req(req, config)
        req.current_action_at = Time.now

        peer = Peer.find_peer(req.torrent, req.user, req.ip, req.port)
        
        unless peer
          Peer.create(req.attributes) unless req.stopped?
        else
          req.last_action_at = peer.last_action_at
          req.set_offsets(peer.uploaded, peer.downloaded)          
          increment_user_counters(req, config[:bonus_rules])
          unless req.stopped?
            req.torrent.add_snatch(req.user) if req.completed?            
            peer.refresh_announce(req.attributes)
          else
            peer.destroy
          end          
        end
        AnnounceLog.create(req.attributes) if config[:log_announces]
      end

      def increment_user_counters(req, bonus_rules)
        up_offset = req.up_offset
        if req.seeder? && bonus_rules[:seeding]
          up_offset += (req.up_offset * bonus_rules[:seeding]).to_i # bonus for seeding
        end
        req.user.increment_counters(up_offset, req.down_offset)
      end

      def prepare_announce_resp(req, resp, config)
        resp.interval     = config[:announce_interval_seconds]
        resp.min_interval = config[:announce_min_interval_seconds]
        resp.complete     = req.torrent.seeders_count
        resp.incomplete   = req.torrent.leechers_count
        unless req.stopped?
          resp.compact    = req.compact
          resp.no_peer_id = req.no_peer_id
          resp.peers      = Peer.find_for_announce_resp(req.torrent, req.user, req.numwant)
        end
      end
  end
end


  