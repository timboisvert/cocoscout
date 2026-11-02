# frozen_string_literal: true

# A big run of bank rules (more lines than BankRules::IN_REQUEST), in the
# background: every line waiting, then a notification to whoever asked.
class BankRulesApplyJob < ApplicationJob
  queue_as :default

  def perform(organization_id, user_id = nil, rule_id = nil)
    org = Organization.find_by(id: organization_id)
    return unless org

    user = user_id && User.find_by(id: user_id)
    rules = rule_id ? org.bank_rules.where(id: rule_id).to_a : org.bank_rules.order(:id).to_a
    result = BankRules.apply!(org, rules: rules, by: user)
    notify(org, user, result) if user
  ensure
    Rails.cache.delete(BankRules.applying_key(org)) if org
  end

  private

  def notify(org, user, result)
    Notifier.deliver(
      user: user, category: "books", kind: "bank_rules_applied", template_key: "bank_rules_applied",
      variables: { recipient_name: (user.person&.name.presence || "there"), organization_name: org.name, dealt_with: result.dealt_with,
                   recorded: result.recorded, ignored: result.ignored, to_deal_with: org.bank_statement_lines.to_deal_with.count,
                   bank_url: Rails.application.routes.url_helpers.manage_money_bank_url(**url_options) },
      path: Rails.application.routes.url_helpers.manage_money_bank_path, organization: org
    )
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end
