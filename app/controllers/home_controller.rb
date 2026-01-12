# frozen_string_literal: true

class HomeController < ApplicationController
  allow_unauthenticated_access

  # Use the public facing layout
  layout "home"

  def index; end

  # New homepage preview
  def new_home; end
  def new_performers; end
  def new_producers; end
end
