
class CommentsController < ApplicationController
  before_filter :login_required
  before_filter :admin_mod_required, :only => :show

  def show
    logger.debug ':-) comments_controller.show'
    @comment = Comment.find params[:id]
  end

  def new
    logger.debug ':-) comments_controller.new'
    @torrent = Torrent.find params[:torrent_id]
    access_denied if @torrent.locked? && !logged_user.admin_mod?
    unless params[:body].blank?
      @torrent.add_comment params, logged_user
      flash[:comment_notice] = t('controller.comments.new.success')
    else
      flash[:comment_error] = t('controller.comments.new.empty')
    end
    redirect_to torrents_path(:action => 'show', :id => @torrent, :page => 'last', :anchor => 'comments')
  end

  def quote
    logger.debug ':-) comments_controller.quote'
    @comment = Comment.find params[:id]
  end

  def edit
    logger.debug ':-) comments_controller.edit_comment'
    @comment = Comment.find params[:id]
    access_denied unless @comment.editable_by? logged_user
    if request.post?
      logger.debug ':-) post request'
      unless cancelled?
        unless params[:body].blank?
          @comment.edit params, logged_user
          logger.debug ':-) comment saved'
          flash[:comment_notice] = t('controller.comments.edit.success')
          redirect_to torrents_path(:action => 'show', :id => @comment.torrent_id, :page => params[:page], :anchor => 'comments')
        else
          flash[:error] = t('controller.comments.edit.empty')
        end
      else
        redirect_to torrents_path(:action => 'show', :id => @comment.torrent_id, :page => params[:page], :anchor => 'comments')
      end
    end
  end

  def report
    logger.debug ':-) comments_controller.report'
    @comment = Comment.find params[:id]
    if request.post?
      unless cancelled?
        unless params[:reason].blank?
          target_path = comments_path(:torrent_id => @comment.torrent_id, :action => 'show', :id => @comment)
          Report.create @comment, target_path, logged_user, params[:reason]
          flash[:notice] = t('controller.comments.report.success')
          redirect_to torrents_path(:action => 'show', :id => @comment.torrent_id, :page => params[:page])
        else
          flash.now[:error] = t('controller.comments.report.reason_required')
        end
      else
        redirect_to torrents_path(:action => 'show', :id => @comment.torrent_id, :page => params[:page])
      end
    end
  end
end
