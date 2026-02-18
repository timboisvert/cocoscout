# frozen_string_literal: true

class SignUpShortlinkController < ApplicationController
  allow_unauthenticated_access

  def show
    sign_up_form = SignUpForm.find_by!(short_code: params[:code])
    redirect_to my_sign_up_entry_path(params[:code]), allow_other_host: false
  end
end
