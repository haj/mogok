
class LogsController < ApplicationController
  before_filter :logged_in_required
  
  def index
    logger.debug ':-) logs_controller.index'        
    params[:keywords] = ApplicationHelper.process_search_keywords params[:keywords]
    params[:order_by], params[:desc] = 'created_at', '1' if params[:order_by].blank?
    
    @logs = Log.search params, current_user, :per_page => APP_CONFIG[:page_size][:logs]
  end
end
