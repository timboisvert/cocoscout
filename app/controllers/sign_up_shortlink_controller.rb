# frozen_string_literal: true

class SignUpShortlinkController < ApplicationController
  allow_unauthenticated_access

  def show
    sign_up_form = SignUpForm.find_by(short_code: params[:code])

    if sign_up_form
      redirect_to sign_up_form.public_url_path, allow_other_host: false
    else
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end
  end
end
