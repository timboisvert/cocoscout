# frozen_string_literal: true

# Sends a Notification (V1.1 plan §9): records it in the person's
# Notifications list and pushes it to their phones if their switch for its
# group is on. Email stays with each area's own mailer, as it was.
#
# The words come from the event's ContentTemplate: its push text if it has
# one, else its subject, so copy never lives in code (all copy via templates).
class Notifier
  def self.deliver(user:, category:, kind:, template_key:, variables: {}, path: nil, organization: nil, subject: nil, reply_path: nil, title: nil)
    group = NotificationGroups.find(category)
    vars = variables.transform_keys(&:to_s)
    title ||= ContentTemplateService.render_push_body(template_key, vars).presence ||
              ContentTemplateService.render_subject(template_key, vars)

    notification = user.notifications.create!(
      category: group.key, kind: kind.to_s, title: title.to_s.squish.truncate(240), path: local_path(path),
      reply_path: local_path(reply_path), organization: organization, subject: subject
    )
    push(notification) if user.notification_push?(group.key)
    notification
  end

  # A notice that arrives already rendered, from MessageService.create_message
  # for a template in NotificationGroups::TEMPLATES: the words are the
  # template's (push text, else subject); body keeps the full message for the
  # notification's own page and the digest. path is the body's first link to
  # this site, else nil (the notification opens its own page). digest: the
  # unread digest owes it an email, as it did when it was a message.
  # push: false when a Message carries the manager's words and pushes itself
  # (one push per notice).
  def self.deliver_rendered(user:, category:, kind:, subject:, body:, push_body: nil, organization: nil, digest: false, push: true)
    group = NotificationGroups.find(category)
    html = body.respond_to?(:to_trix_html) ? body.to_trix_html : body.to_s
    notification = user.notifications.create!(
      category: group.key, kind: kind.to_s, title: (push_body.presence || subject).to_s.squish.truncate(240),
      body: html.presence, path: first_link_path(html), organization: organization,
      digest: digest && user.message_digest_enabled? && user.notification_email?(group.key)
    )
    push(notification) if push && user.notification_push?(group.key)
    notification
  end

  # The first link in a notice's body that points at this site, as a path.
  def self.first_link_path(html)
    return nil if html.blank?

    host = (Rails.application.config.action_mailer.default_url_options || {})[:host]
    Nokogiri::HTML.fragment(html).css("a[href]").each do |a|
      href = a["href"].to_s
      next if href.start_with?("mailto:", "tel:", "#")

      uri = URI.parse(href) rescue next
      next unless uri.host.nil? || uri.host == host || uri.host&.end_with?("cocoscout.com")

      path = local_path(href)
      return path if path.present? && path != "/"
    end
    nil
  end

  def self.push(notification)
    user = notification.user
    PushNotificationService.notify(
      user,
      title: notification.organization&.name || "CocoScout",
      body: notification.title,
      data: { type: "notification", path: Rails.application.routes.url_helpers.open_notification_path(notification), notification_id: notification.id.to_s },
      badge: user.unread_message_count + user.unread_notification_count
    )
  end

  # Links arrive as full URLs from email variables; the list keeps the path.
  def self.local_path(url)
    return nil if url.blank?

    uri = URI.parse(url.to_s)
    [ uri.path.presence || "/", uri.query ].compact.join("?")
  rescue URI::InvalidURIError
    nil
  end

  private_class_method :push
end
