
class UsersController < ApplicationController
  before_filter :logged_in_required
  before_filter :admin_required, :only => [:new, :destroy]
    
  def index
    logger.debug ':-) users_controller.index'
    params[:order_by] = 'username' if params[:order_by].blank?

    @users = User.search params, current_user, :per_page => APP_CONFIG[:page_size][:users]
    @users.desc_by_default = APP_CONFIG[:desc_by_default][:users]
    
    @roles = Role.all_for_search
    @countries = Country.cached_all
  end 
  
  def show
    logger.debug ':-) users_controller.show'
    @user = User.find params[:id]
    if @user.under_ratio_watch? && @user == current_user && flash.empty?
      flash.now[:ratio_watch] = t('ratio_watch', :until => l(@user.ratio_watch_until, :format => :date))
    end
  end  

  def new
    logger.debug ':-) users_controller.new'
    @user = User.new params[:user]
    if request.post?
      unless cancelled?
        if @user.valid?
          @user.inviter = current_user
          @user.save
          logger.debug ":-) user created. id: #{@user.id}"
          redirect_to_user
        else
          logger.debug ':-o user not created'
          @user.password = @user.password_confirmation = ''
        end
      else
        redirect_to :action => 'index'
      end
    end
    set_collections
  end
  
  def edit
    logger.debug ':-) users_controller.edit'
    @user = User.find params[:id]
    access_denied unless @user.editable_by? current_user
    if request.post?
      unless cancelled?
        if @user.edit(params[:user], current_user, params[:current_password], params[:update_counters] == '1')
          logger.debug ':-) user edited'
          flash[:notice] = t('success')
          redirect_to_user
        else
          logger.debug ':-o user not edited'
          @user.password = @user.password_confirmation = ''
        end
      else
        redirect_to_user
      end
    end
    set_collections    
    @roles = Role.all_for_user_edition(current_user) if current_user.admin?
  end

  def destroy
    logger.debug ':-) users_controller.destroy'
    @user = User.find params[:id]
    access_denied if !@user.editable_by?(current_user) || @user == current_user
    if request.post?
      unless cancelled?
        @user.destroy_with_log(current_user)              
        flash[:notice] = t('success')        
        redirect_to :action => 'index'
      else
        redirect_to_user
      end
    end
  end
  
  def reset_passkey
    logger.debug ':-) users_controller.reset_passkey'
    @user = User.find params[:id]
    access_denied if @user != current_user && !current_user.admin?
    if request.post?
      unless cancelled?
        @user.reset_passkey_with_notification(current_user)
        flash[:notice] = t('success')
      end
      redirect_to_user
    end
  end

  def edit_staff_info
    logger.debug ':-) users_controller.edit_staff_info'
    ticket_required(:staff)
    @user = User.find params[:id]
    if request.post?
      unless cancelled?
        @user.update_attribute :staff_info, params[:staff_info]
      end
      redirect_to_user
    end
  end

  def report
    logger.debug ':-) users_controller.report'
    @user = User.find params[:id]
    if request.post?
      unless cancelled?
        unless params[:reason].blank?
          @user.report current_user, params[:reason], users_path(:action => 'show', :id => @user)
          flash[:notice] = t('success')
          redirect_to_user
        else
          flash.now[:error] = t('reason_required')
        end
      else
        redirect_to_user
      end
    end
  end

  def my_bookmarks
    logger.debug ':-) users_controller.bookmarks'
    @torrents = current_user.paginate_bookmarks params, :per_page => 20
    @torrents.each {|t| t.bookmarked = true} if @torrents
  end

  def my_uploads
    logger.debug ':-) users_controller.uploads'
    params[:order_by], params[:desc]= 'created_at', '1' if params[:order_by].blank?
    @torrents = current_user.paginate_uploads params, :per_page => APP_CONFIG[:page_size][:user_history]
    set_bookmarked_flags @torrents
    @torrents.desc_by_default = APP_CONFIG[:desc_by_default][:torrents] unless @torrents.blank?
  end

  def my_wishes
    logger.debug ':-) users_controller.wishes'
    params[:order_by], params[:desc]= 'created_at', '1' if params[:order_by].blank?
    @wishes = current_user.paginate_wishes params, :per_page => APP_CONFIG[:page_size][:wishes]
    @wishes.desc_by_default = APP_CONFIG[:desc_by_default][:wishes] unless @wishes.blank?
  end

  def stuck
    logger.debug ':-) users_controller.stuck'
    @torrents = current_user.paginate_stuck params, :per_page => 20
    set_bookmarked_flags @torrents
  end
  
  def show_activity
    logger.debug ':-) users_controller.show_activity'
    @seeding = params[:seeding] == '1'
    @user = User.find params[:id]
    if !@seeding && @user != current_user && !current_user.admin?
      access_denied unless @user.display_downloads?
    end
    @peers = @user.paginate_peers params, :per_page => APP_CONFIG[:page_size][:user_activity]
  end  
  
  def show_uploads
    logger.debug ':-) users_controller.show_uploads'
    params[:order_by], params[:desc]= 'created_at', '1'
    @user = User.find params[:id]
    @torrents = @user.paginate_uploads params, :per_page => APP_CONFIG[:page_size][:user_history]
  end  
  
  def show_snatches
    logger.debug ':-) users_controller.show_snatches'
    @user = User.find params[:id]
    if @user != current_user && !current_user.admin?
      access_denied unless @user.display_downloads?
    end
    @snatches = @user.paginate_snatches params, :per_page => APP_CONFIG[:page_size][:user_history]
  end
  
  private

    def redirect_to_user(u = nil)
      redirect_to :action => 'show', :id => u || @user
    end

    def set_collections
      @genders = Gender.cached_all
      @countries = Country.cached_all
      @styles = Style.cached_all
    end

    def set_bookmarked_flags(torrents)
      return if torrents.blank?
      unless current_user.bookmarks.blank?
        torrents.each do |t|
          t.bookmarked = true if current_user.bookmarks.detect {|b| b.torrent_id == t.id }
        end
      end
    end
end



















