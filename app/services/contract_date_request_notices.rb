# frozen_string_literal: true

# Who is notified about a contractor's request on a contract date, and in
# what words (ContractDateRequestTemplates). Notifications only, never an
# email. The organization's side goes to the people it chose for contract
# notices (Contract settings → Notifications); the contractor's side goes to
# whoever asked. Nobody in a cast is ever notified of a request: they are
# notified about a date only when it actually changes.
class ContractDateRequestNotices
  class << self
    def asked(request)
      to_organization(request, kind: "contract_date_request_asked", template: "contract_date_request_asked",
                               extra: { asks_words: request.asks_words })
    end

    def reminder(request)
      to_organization(request, kind: "contract_date_request_reminder", template: "contract_date_request_reminder",
                               extra: { request_phrase: request.request_phrase })
    end

    def done(request)
      to_asker(request, kind: "contract_date_request_done", template: "contract_date_request_done",
                        extra: { outcome_words: request.outcome_words })
    end

    def kept(request)
      to_asker(request, kind: "contract_date_request_kept", template: "contract_date_request_kept",
                        extra: { kept_words: request.kept_words, note: request.answer_note.to_s })
    end

    def amending(request)
      to_asker(request, kind: "contract_date_request_amending", template: "contract_date_request_amending",
                        extra: { request_phrase: request.request_phrase })
    end

    private

    def to_organization(request, kind:, template:, extra:)
      contract = request.contract
      path = routes.manage_contract_path(contract)
      contract.organization.contract_notification_recipients.filter_map(&:user).uniq.each do |user|
        deliver(user, request, kind: kind, template: template, path: path, variables: extra.merge(contract_url: path))
      end
    end

    def to_asker(request, kind:, template:, extra:)
      path = routes.my_contracts_path
      deliver(request.requested_by, request, kind: kind, template: template, path: path, variables: extra.merge(contracts_url: path))
    end

    def deliver(user, request, kind:, template:, path:, variables:)
      contract = request.contract
      Notifier.deliver(user: user, category: "contracts", kind: kind, template_key: template, path: path,
                       organization: contract.organization, subject: contract,
                       variables: { contractor_name: contract.contractor_name, organization_name: contract.organization.name,
                                    production_name: contract.production&.name || contract.production_name.to_s,
                                    note: request.note.to_s }.merge(variables))
    rescue StandardError => e
      # A notice that can't be sent never undoes the request or the answer.
      Rails.logger.error("[ContractDateRequestNotices] request #{request.id} #{kind}: #{e.class}: #{e.message}")
      nil
    end

    def routes = Rails.application.routes.url_helpers
  end
end
