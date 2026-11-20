# frozen_string_literal: true

# Closes requests for more comps nobody decided before their date started,
# and tells whoever requested them (CompRequest.close_started!).
class CompRequestExpiryJob < ApplicationJob
  queue_as :default

  def perform
    CompRequest.close_started!
  end
end
