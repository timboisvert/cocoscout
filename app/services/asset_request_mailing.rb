# frozen_string_literal: true

# Sends a production's visual asset request (Tim, 2026-11-19): the email,
# with the manager's own subject and message, what is still needed, and the
# one button, to each address. Everyone asked who has an account is notified
# too: the people on the production's contract (the first time; it opens the
# page on My Contracts) and anyone else emailed (it opens the link's page).
# A reminder is the email alone.
class AssetRequestMailing
  def self.deliver!(request, emails, sender:, reminder: false)
    new(request, sender: sender, reminder: reminder).deliver!(emails)
  end

  def initialize(request, sender:, reminder: false)
    @request = request
    @production = request.production
    @organization = @production.organization
    @sender = sender
    @reminder = reminder
  end

  def deliver!(emails)
    variables = email_variables
    emails.each do |email|
      AppMailer.with(template_key: "visual_assets_request", to: email, variables: variables).send_template.deliver_later
    end
    return if @reminder

    notified = @request.sent_at.present? ? [] : notify_contract_people
    notify_emailed_accounts(emails, except: notified)
  end

  private

  def email_variables
    subject = @request.subject.presence || "Images and details we need for #{@production.name}"
    {
      "subject" => @reminder ? "A reminder: #{subject}" : subject,
      "message_html" => message_html,
      "list_html" => list_html,
      "upload_url" => @request.url,
      "sender_name" => @sender&.person&.name || @organization.name,
      "organization_name" => @organization.name,
      "production_name" => @production.name
    }
  end

  def message_html
    words = @request.message.to_s.strip
    words = AssetRequest.default_message(@production) if words.blank?
    words.split(/\n{2,}/).map { |para| "<p>#{ERB::Util.html_escape(para).gsub("\n", '<br>')}</p>" }.join
  end

  # What is still needed: required first, then the optional ones, named.
  def list_html
    assets = ProductionAssets.new(@production)
    missing = assets.items.reject(&:present?)
    return "<p>Everything #{ERB::Util.html_escape(@organization.name)} requires has been added. You can still change anything on the page.</p>" if missing.empty?

    rows = missing.sort_by { |item| item.spec.required? ? 0 : 1 }.map do |item|
      spec = item.spec
      words = spec.image? ? "#{spec.name}, #{spec.print? ? "#{spec.inches(spec.width)} × #{spec.inches(spec.height)} inches" : "#{spec.width} × #{spec.height}"}" : spec.name
      words += " (optional)" unless spec.required?
      "<li>#{ERB::Util.html_escape(words)}</li>"
    end
    "<ul>#{rows.join}</ul>"
  end

  def notify_contract_people
    contract = @production.contract
    return [] unless contract

    users = contract.people_with_access.filter_map(&:user).uniq
    users.each { |user| notify(user, Rails.application.routes.url_helpers.my_contract_assets_path(contract)) }
    users
  end

  # Anyone else emailed who has a CocoScout account (a designer, say; Tim,
  # 2026-11-19): the same notification, opening the link's page, since they
  # have no contract to open it from. Someone on the contract isn't told twice.
  def notify_emailed_accounts(emails, except:)
    return if emails.empty?

    path = Rails.application.routes.url_helpers.asset_request_path(token: @request.token)
    on_contract = @production.contract&.people_with_access&.filter_map(&:user_id) || []
    User.where("LOWER(email_address) IN (?)", emails.map(&:downcase)).where.not(id: except.map(&:id) + on_contract)
        .find_each { |user| notify(user, path) }
  end

  def notify(user, path)
    Notifier.deliver(user: user, category: "visual_assets", kind: "visual_assets_requested", template_key: "visual_assets_requested",
                     variables: { organization_name: @organization.name, production_name: @production.name },
                     path: path, organization: @organization, subject: @request)
  end
end
