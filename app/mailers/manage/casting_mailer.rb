# frozen_string_literal: true

module Manage
  class CastingMailer < ApplicationMailer
    def cast_email(person, show, title, body, sender)
      @person = person
      @show = show
      @title = title
      @body = body
      @sender = sender
      mail(to: person.email, subject: title)
    end
  end
end
