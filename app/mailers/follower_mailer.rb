# frozen_string_literal: true

# Email to followers (Mailing lists, V1.1), in the organization's own look:
# its logo and color at the top, the manager's words, shows as blocks with a
# Buy tickets button, and a footer with why they got it, the postal address
# and an unsubscribe link. Sent on its own Mailgun domain
# (FOLLOWERS_MAIL_DOMAIN, e.g. news.cocoscout.com) so a bad list can never
# hurt sign-in or payment mail on cocoscout.com. CocoScout's own notes
# about lists (a share, an export) are FollowerNoticeMailer.
class FollowerMailer < ApplicationMailer
  include TicketingHelper

  skip_before_action :attach_logo
  layout "follower_mailer"

  def follower_email(delivery)
    @delivery = delivery
    @follower = delivery.follower
    @follower_email = delivery.follower_email
    @organization = @follower_email.organization
    @unsubscribe_url = follower_unsubscribe_url(token: @follower.unsubscribe_token, **default_url_options)
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    message.mailgun_variables = { "delivery_id" => delivery.id.to_s } if message.respond_to?(:mailgun_variables=)
    compose(to: @follower.email, first_name: @follower.first_name)
  end

  # A copy to the manager, with a line saying it's a test.
  def test_email(follower_email, user)
    @follower_email = follower_email
    @organization = follower_email.organization
    @test_note = FollowerTemplates.render("follower_email_test_note", subject: follower_email.subject)[:body]
    @unsubscribe_url = nil
    compose(to: user.email_address, first_name: user.person&.name.to_s.split.first, subject_prefix: "[Test] ")
  end

  # The email as a follower would get it, for the composer's preview.
  def preview(follower_email, first_name)
    @follower_email = follower_email
    @organization = follower_email.organization
    @unsubscribe_url = "#unsubscribe"
    compose(to: "preview@cocoscout.com", first_name: first_name)
  end

  private

  def compose(to:, first_name:, subject_prefix: "")
    @accent = @organization.email_accent
    @body_html = personalize(@follower_email.body.to_s, first_name)
    @shows = @follower_email.shows.map { |show| show_block(show) }
    @footer_words = FollowerTemplates.render("follower_email_footer", organization_name: @organization.name)[:body]
    @preheader = @follower_email.preheader
    headers["X-CocoScout-Stream"] = "followers"
    domain = ENV["FOLLOWERS_MAIL_DOMAIN"].presence
    sender = domain ? "news@#{domain}" : "info@cocoscout.com"
    options = {
      to: to,
      from: %("#{@organization.name.delete('"')} via CocoScout" <#{sender}>),
      subject: "#{subject_prefix}#{@follower_email.subject}"
    }
    reply_to = TicketingProfile.find_by(organization: @organization)&.support_email.presence
    options[:reply_to] = reply_to if reply_to
    options[:domain] = domain if domain
    mail(options) { |format| format.html { render "follower_mailer/follower_email" } }
  end

  # {{first_name}} in their words becomes each follower's own.
  def personalize(html, first_name)
    name = ERB::Util.html_escape(first_name.presence || "there")
    with_name = html.gsub(/\{\{\s*first_name\s*\}\}/, name)
    tag_links(with_name)
  end

  # Links to this organization's ticket pages carry the email's campaign, so
  # a ticket bought from it counts on the email's page.
  def tag_links(html)
    html.gsub(%r{href="([^"]*/tickets/[^"]*)"}) { %(href="#{with_campaign(Regexp.last_match(1))}") }
  end

  def with_campaign(url)
    uri = URI.parse(url)
    query = Rack::Utils.parse_query(uri.query.to_s).merge("utm_source" => "cocoscout", "utm_medium" => "email",
                                                          "utm_campaign" => @follower_email.campaign_key)
    uri.query = query.to_query
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  def show_block(show)
    production = show.production
    listing = show.ticket_listing
    profile = TicketingProfile.find_by(organization: @organization)
    url = if listing && profile && listing.status != "draft"
      with_campaign(tickets_event_url(org: profile.slug, event: listing.slug, **default_url_options))
    end
    poster = show.safe_poster_variant(:small) || production.safe_poster_variant(:small)
    {
      title: show.secondary_name.presence || production.name,
      when: show.date_and_time.strftime("%a, %b %-d · %-l:%M %p"),
      place: show.location&.name,
      url: url,
      poster_url: poster ? Rails.application.routes.url_helpers.rails_representation_url(poster, **default_url_options) : nil,
      initials: production.respond_to?(:initials) ? production.initials : production.name.to_s.first(2).upcase
    }
  end
end
