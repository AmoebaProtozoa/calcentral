class BlogFeedController < ApplicationController

  caches_action(:get_latest_release_notes, :expires_in => BlogFeed.expires_in)

  def get_latest_release_notes
    render :json => BlogFeed.new.get_latest_release_notes
  end

end
