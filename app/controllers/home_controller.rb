# frozen_string_literal: true

class HomeController < ApplicationController
  allow_unauthenticated_access

  # Use the public facing layout
  layout "home"

  def index; end

  # New homepage preview
  def new_home; end

  # Producer-first repositioning preview (three tiers) — /new
  def new_landing; end
  def new_performers; end
  def new_producers; end

  # Free vs. Pro plan comparison
  def pricing; end
end
