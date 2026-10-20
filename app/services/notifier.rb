# frozen_string_literal: true

# Sends a Notification (V1.1 plan §9): records it in the person's
# Notifications list and pushes it to their phones if their switch for its
# group is on. Email stays with each area's own mailer, as it was.
#
# The words come from the event's ContentTemplate: its push text if it has
# one, else its subject, so copy never lives in code (all copy via templates).
class Notifier
  def self.deliver(user:, category:, kind:, template_key:, variables: {}, path: nil, organization: nil, subject: nil, reply_path: nil)
    group = NotificationGroups.find(category)
    vars = variables.transform_keys(&:to_s)
    title = ContentTemplateService.render_push_body(template_key, vars).presence ||
            ContentTemplateService.render_subject(template_key, vars)

    notification = user.notifications.create!(
      category: group.key, kind: kind.to_s, title: title.to_s.squish.truncate(240), path: local_path(path),
      reply_path: local_path(reply_path), organization: organization, subject: subject
    )
    push(notification) if user.notification_push?(group.key)
    notification
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
