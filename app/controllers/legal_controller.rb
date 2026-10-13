# frozen_string_literal: true

class LegalController < ApplicationController
  allow_unauthenticated_access

  layout "home"

  def terms; end

  def privacy; end

  # How to reach us: the App Store's support page.
  def support; end
end
