# frozen_string_literal: true

class ShoutoutMailer < ApplicationMailer
  def shoutout_received(shoutout)
    @shoutout = shoutout
    @recipient = shoutout.shoutee
    @author = shoutout.author

    mail(
      to: @recipient.email,
      subject: "#{@author.name} gave you a shoutout on CocoScout!"
    )
  end
end
