# frozen_string_literal: true

class AddVideoUrlToAuditionRequests < ActiveRecord::Migration[7.0]
  def change
    add_column :audition_requests, :video_url, :string
  end
end
