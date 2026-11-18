# frozen_string_literal: true

# The W-9 ask says why the person is getting it (Tim, 2026-11-12): the phone
# notification only said "Stars & Garters needs your tax info", and someone
# reading it cold had no idea why. Both the request and the weekly reminder
# now say it in the notification itself: they're on staff, they're paid as an
# independent contractor, and the form is what a 1099 is made from.
# Only staff are ever asked, so the words can say "staff".
class W9RequestSaysWhy < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  COPY = {
    "staff_w9_request" => {
      push_body: "{{organization_name}} pays you as staff, so they need a Form W-9 from you to send your 1099 at tax time. It takes about two minutes.",
      body: <<~HTML
        <p>Hi {{first_name}},</p>
        <p>You're on staff at <strong>{{organization_name}}</strong>, and they pay you as an independent contractor rather than an employee. That means they need a Form W-9 from you on file, so they can send you a 1099 at tax time.</p>
        <p>It takes about two minutes: your legal name, address, and your Social Security number or EIN.</p>
        <p><a href="{{w9_url}}">Fill out your W-9 →</a></p>
        <p>Your tax ID is encrypted and only shared with {{organization_name}}.</p>
      HTML
    },
    "staff_w9_reminder" => {
      push_body: "{{organization_name}} is still waiting on your Form W-9. They pay you as staff and need it to send your 1099 at tax time.",
      body: <<~HTML
        <p>Hi {{first_name}},</p>
        <p>Just a nudge: <strong>{{organization_name}}</strong> is still waiting on your Form W-9. You're on staff there and paid as an independent contractor, so they need it on file to send you a 1099 at tax time.</p>
        <p>It takes about two minutes: your legal name, address, and your Social Security number or EIN.</p>
        <p><a href="{{w9_url}}">Fill out your W-9 →</a></p>
        <p>Your tax ID is encrypted and only shared with {{organization_name}}.</p>
      HTML
    }
  }.freeze

  def up
    COPY.each do |key, copy|
      Template.where(key: key).find_each { |template| template.update!(copy) }
    end
  end

  def down
    Template.where(key: COPY.keys).update_all(push_body: nil)
  end
end
