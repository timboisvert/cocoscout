class MessageNotificationMailer < ApplicationMailer
  # Send digest of unread messages after user hasn't checked their inbox
  # user: The User who has unread messages
  # unread_threads: Array of { message:, unread_count: } hashes
  def unread_digest(user:, unread_threads:)
    @user = user
    @unread_threads = unread_threads

    return unless @user&.email_address
    return if unread_threads.empty?

    # Build thread list HTML
    thread_list_html = build_thread_list_html(unread_threads)

    template_variables = {
      recipient_name: @user.person&.first_name || @user.email_address.split("@").first,
      inbox_url: my_messages_url,
      thread_list: thread_list_html
    }

    template = ContentTemplateService.render("unread_digest", template_variables)

    mail(
      to: @user.email_address,
      subject: template[:subject]
    ) do |format|
      format.html { render html: template[:body].html_safe, layout: "mailer" }
      format.text { render plain: strip_tags(template[:body]).gsub(/\s+/, " ").strip }
    end
  end

  private

  def build_thread_list_html(unread_threads)
    html = '<div style="background-color: #f9fafb; border-radius: 12px; padding: 16px; margin-bottom: 24px;">'

    unread_threads.each_with_index do |thread, index|
      border_style = index > 0 ? "border-top: 1px solid #e5e7eb; padding-top: 12px; margin-top: 12px;" : ""
      production_info = thread[:message].production ? "via #{thread[:message].production.name} · " : ""

      html += <<~THREAD
        <div style="#{border_style}">
          <p style="margin: 0 0 4px 0; font-weight: 600; color: #111827; font-size: 15px;">
            #{ERB::Util.html_escape(thread[:message].subject)}
          </p>
          <p style="margin: 0; color: #6b7280; font-size: 14px;">
            #{production_info}<span style="color: #db2777; font-weight: 500;">#{thread[:unread_count]} unread #{"message".pluralize(thread[:unread_count])}</span>
          </p>
        </div>
      THREAD
    end

    html += "</div>"
    html
  end
end
