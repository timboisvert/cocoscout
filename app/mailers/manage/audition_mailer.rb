# frozen_string_literal: true

module Manage
  class AuditionMailer < ApplicationMailer
    def casting_notification(person, production, email_body)
      @person = person
      @production = production
      @email_body = email_body

      mail(
        to: person.email,
        subject: "Audition Results for #{production.name}"
      )
    end

    def invitation_notification(person, production, email_body)
      @person = person
      @production = production
      @email_body = email_body

      mail(
        to: person.email,
        subject: "#{production.name} Auditions"
      )
    end

    def audition_request_notification(recipient_user, audition_request)
      @recipient = recipient_user
      @audition_request = audition_request
      @requestable = audition_request.requestable
      @production = audition_request.audition_cycle.production
      @audition_cycle = audition_request.audition_cycle

      mail(
        to: recipient_user.email_address,
        subject: "[#{@production.name}] New audition request from #{@requestable.name}"
      )
    end

    def talent_left_production(recipient_user, production, person, groups)
      @recipient = recipient_user
      @production = production
      @person = person
      @groups = groups

      mail(
        to: recipient_user.email_address,
        subject: "[#{@production.name}] #{@person.name} has left the talent pool"
      )
    end
  end
end
