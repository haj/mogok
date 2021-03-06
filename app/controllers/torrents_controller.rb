
class TorrentsController < ApplicationController
  include TrackerHelper
  before_filter :logged_in_required
  before_filter :admin_mod_required, :only => [:switch_lock_comments, :activate]
  cache_sweeper :torrents_sweeper, :only => [:upload, :remove]

  class TorrentFileError < StandardError
    attr_accessor :args
    
    def initialize(error_key, args)
      super error_key
      self.args = args
    end
  end

  def index
    logger.debug ':-) torrents_controller.index'
    params[:keywords] = ApplicationHelper.process_search_keywords params[:keywords], 3
    params[:order_by], params[:desc]= 'created_at', '1' if params[:order_by].blank?
    
    @perform_cache = index_perform_cache?
    
    @fragment_name = "torrents.index.page.#{params[:page] || 1}"
    @search_box_fragment_name = 'torrents.index.search_box'

    if !@perform_cache || (@perform_cache && expire_timed_fragment(@fragment_name)) # mogok_timed_fragment_cache plugin
      @torrents = Torrent.search params, current_user, :per_page => APP_CONFIG[:page_size][:torrents]
      @torrents.desc_by_default = APP_CONFIG[:desc_by_default][:torrents] unless @torrents.blank?
      @category = Category.find params[:category_id] unless params[:category_id].blank?
    end
    set_collections
  end  

  def show
    logger.debug ':-) torrents_controller.show'
    @torrent = Torrent.find_by_id params[:id]
    if torrent_available?
      @torrent.set_bookmarked current_user
      @mapped_files = MappedFile.cached_by_torrent(@torrent)
      @comments = @torrent.paginate_comments params, :per_page => APP_CONFIG[:page_size][:torrent_comments]
      @comments.html_anchor  = 'comments' if @comments
    end
  end  
  
  def edit
    logger.debug ':-) torrents_controller.edit'
    @torrent = Torrent.find_by_id params[:id]
    if torrent_available?
      access_denied unless @torrent.editable_by? current_user
      if request.post?
        unless cancelled?
          if @torrent.edit(params[:torrent], current_user, params[:reason])
            logger.debug ':-) torrent edited'            
            flash[:notice] = t('success')
            redirect_to_torrent
          else
            logger.debug ':-o torrent not edited'
          end
        else
          redirect_to_torrent
        end
      end
      set_collections
      @category = @torrent.category
    else
      render :template => 'torrents/unavailable'
    end
  end
  
  def remove
    logger.debug ':-) torrents_controller.remove'
    @torrent = Torrent.find_by_id params[:id]
    if torrent_available?
      access_denied unless @torrent.editable_by? current_user
      if request.post?
        unless cancelled?
          if !@torrent.active? || params[:destroy] == '1'
            @torrent.destroy_with_notification(current_user, params[:reason])
            flash[:notice] = t('destroyed')
            redirect_to :action => 'index'
          else
            @torrent.inactivate(current_user, params[:reason])
            if current_user.admin_mod?
              flash[:notice] = t('inactivated')
              redirect_to_torrent
            else
              @torrent.report current_user, t('inactivated_report'), torrents_path(:action => 'show', :id => @torrent)
              @args = {:title => t('inactivated_title'), :message => t('inactivated_message')}
              render :template => 'misc/message'
            end
          end
        else
          redirect_to_torrent
        end
      end
    else
      render :template => 'torrents/unavailable'
    end
  end  

  def activate
    logger.debug ':-) torrents_controller.activate'
    t = Torrent.find params[:id]
    t.activate current_user
    flash[:notice] = t('success')
    redirect_to_torrent t
  end

  def report
    logger.debug ':-) torrents_controller.report'
    @torrent = Torrent.find_by_id params[:id]
    if torrent_available?
      if request.post?
        unless cancelled?
          unless params[:reason].blank?
            @torrent.report current_user, params[:reason], torrents_path(:action => 'show', :id => @torrent)
            flash[:notice] = t('success')
            redirect_to_torrent
          else
            flash.now[:error] = t('reason_required')
          end
        else
          redirect_to_torrent
        end
      end
    else
      render :template => 'torrents/unavailable'      
    end
  end
  
  def bookmark
    logger.debug ':-) torrents_controller.bookmark'
    @torrent = Torrent.find params[:id]
    @torrent.bookmark_unbookmark current_user
  end

  def switch_lock_comments
    logger.debug ':-) torrents_controller.switch_lock_comments'
    t = Torrent.find params[:id]
    t.toggle! :comments_locked
    redirect_to_torrent t
  end

  def upload
    logger.debug ':-) torrents_controller.upload'    
    @torrent = Torrent.new params[:torrent]
    if request.post?
      access_denied if !APP_CONFIG[:torrents][:upload_enabled] && !current_user.admin?
      begin
        file_data = get_file_data params[:torrent_file]
        @torrent.user = current_user
        if @torrent.parse_and_save(file_data, true)
          flash[:alert] = t('success')
          redirect_to_torrent
        end
      rescue TorrentFileError => e
        logger.debug ":-o torrent file error: #{e.message}"
        @torrent.valid? # check other errors
        @torrent.add_error :torrent_file, e.message, e.args
      end
      @category = @torrent.category
    end
    set_collections
    @category = @categories[0] unless @category
  end 
    
  def download
    logger.debug ':-) torrents_controller.download'
    t = Torrent.find_by_id params[:id]
    if torrent_available?(t)
      t.announce_url = make_announce_url t, current_user
      t.comment = APP_CONFIG[:torrents][:file_comment] if APP_CONFIG[:torrents][:file_comment]
      file_name = TorrentsHelper.torrent_file_name t, APP_CONFIG[:torrents][:file_prefix]
      send_data t.out, :filename => file_name, :type => 'application/x-bittorrent', :disposition => 'attachment'
    else
      render :template => 'torrents/unavailable'
    end
  end

  def show_peers
    logger.debug ':-) torrents_controller.show_peers'
    t = Torrent.find_by_id params[:id]
    @peers = t.paginate_peers params, :per_page => APP_CONFIG[:page_size][:torrent_peers] if t
  end  
  
  def show_snatches
    logger.debug ':-) torrents_controller.show_snatches'
    t = Torrent.find_by_id params[:id]
    @snatches = t.paginate_snatches params, :per_page => APP_CONFIG[:page_size][:torrent_snatches] if t
  end

  def reseed_request
    logger.debug ':-) torrents_controller.reseed_request'
    @torrent = Torrent.find_by_id params[:id]
    access_denied unless @torrent.eligible_for_reseed_request?
    if torrent_available?
      if request.post?
        unless cancelled?
          cost = APP_CONFIG[:torrents][:reseed_request_cost_mb].megabytes
          if current_user.uploaded >= cost
            @torrent.request_reseed current_user, cost, APP_CONFIG[:torrents][:reseed_request_notifications]
            flash[:notice] = t('success')
            redirect_to_torrent
          else
            flash.now[:error] = t('insufficient_upload_credit')
          end
        else
          redirect_to_torrent
        end        
      end
    else
      render :template => 'torrents/unavailable'
    end
  end
    
  private

    def redirect_to_torrent(t = nil)
      redirect_to :action => 'show', :id => t || @torrent
    end

    def torrent_available?(t = nil)
      t ||= @torrent
      !t.blank? && (t.active? || current_user.admin_mod?)
    end

    def set_collections
      @types = Type.cached_all
      @categories = Category.cached_all
      @countries = Country.cached_all
    end

    def torrent_file_error(error_key, args = {})
      raise TorrentFileError.new(error_key, args)
    end

    def get_file_data(f)
      ensure_valid_uploaded_file(f)

      if f.respond_to? :string
        data = f.string
      elsif f.respond_to? :read
        data = f.read
      else
        raise 'unable to handle uploaded file, check how the web server treats file uploads'
      end
      data
    end

    def ensure_valid_uploaded_file(f)
      if f.blank?
        torrent_file_error 'required'
      else
        logger.debug ":-) file uploaded as #{f.class.name}"
        if f.respond_to?(:original_filename) && !f.original_filename.downcase.ends_with?('.torrent')
          torrent_file_error 'type'
        end
        if f.size > APP_CONFIG[:torrents][:file_max_size_kb].kilobytes
          torrent_file_error 'size', :max_size => APP_CONFIG[:torrents][:file_max_size_kb]
        end
      end
    end

    def index_perform_cache?
      !current_user.admin_mod? && # admin_mods can see inactive torrents
      params[:order_by] == 'created_at' && params[:desc] == '1' &&
      params[:keywords].blank? &&
      params[:category_id].blank? &&
      params[:format_id].blank? &&
      params[:country_id].blank? &&
      params[:tags_str].blank? &&
      params[:inactive].blank?
    end
end

