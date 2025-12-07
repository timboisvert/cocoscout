# frozen_string_literal: true

class LegalController < ApplicationController
  allow_unauthenticated_access

  layout "home"

  def terms; end

  def privacy; end
end
