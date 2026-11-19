# frozen_string_literal: true

# Sends a production's visual asset request (Tim, 2026-11-19): the email,
# with the manager's own subject and message, what is still needed, and the
# one button, to each address. Of those, the people with an account who are
# on the production's contract, or on an in-house production's team, are
# notified too. A reminder is the email alone.
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
    notify_people_asked(emails) unless @reminder
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

    rows = missing.each_with_index.sort_by { |item, index| [ item.spec.required? ? 0 : 1, index ] }.map(&:first).map do |item|
      spec = item.spec
      words = spec.image? ? "#{spec.name}, #{spec.print? ? "#{spec.inches(spec.width)} × #{spec.inches(spec.height)} inches" : "#{spec.width} × #{spec.height}"}" : spec.name
      words += " (optional)" unless spec.required?
      "<li>#{ERB::Util.html_escape(words)}</li>"
    end
    "<ul>#{rows.join}</ul>"
  end

  # Of the people emailed, the ones with an account who belong to the show
  # are notified too (Tim, 2026-11-19): on the contract, it opens the page on
  # My Contracts; on an in-house production's team, the link's page. Anyone
  # else emailed (a designer, say) gets the email alone. A reminder is the
  # email alone.
  def notify_people_asked(emails)
    wanted = emails.map(&:downcase)
    return if wanted.empty?

    helpers = Rails.application.routes.url_helpers
    contract = @production.contract
    if contract
      users = contract.people_with_access.select { |person| person.user && asked?(person, wanted) }.map(&:user)
      path = helpers.my_contract_assets_path(contract)
    elsif !@production.type_third_party?
      users = User.where(id: ProductionNotificationSetting.team_user_ids(@production).to_a).includes(:people).select { |user| asked_user?(user, wanted) }
      path = helpers.asset_request_path(token: @request.token)
    else
      return
    end

    users.uniq.reject { |user| user == @sender }.each { |user| notify(user, path) }
  end

  def asked?(person, wanted)
    wanted.include?(person.email.to_s.downcase) || wanted.include?(person.user.email_address.to_s.downcase)
  end

  def asked_user?(user, wanted)
    wanted.include?(user.email_address.to_s.downcase) || user.people.any? { |person| wanted.include?(person.email.to_s.downcase) }
  end

  def notify(user, path)
    Notifier.deliver(user: user, category: "visual_assets", kind: "visual_assets_requested", template_key: "visual_assets_requested",
                     variables: { organization_name: @organization.name, production_name: @production.name },
                     path: path, organization: @organization, subject: @request)
  end
end
