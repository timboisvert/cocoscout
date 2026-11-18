# frozen_string_literal: true

# Sales tax a register (Square) collected, as the books carry it: a day's
# register reaches the books when the day is settled (SettlementPoster),
# and its sales tax goes to Tax to pay the government while the register's
# page says to bring tax in. That money arrives in the bank with the
# register's deposit; it is never set aside in the CocoScout balance.
#
#   owed_total_cents  everything posted, for the books' tax check
#   rows              by register, for settled days in a period (the Sales
#                     tax page and the year's tax summary)
class RegisterSalesTax
  Row = Data.define(:name, :days, :sales_cents, :tax_cents)

  # The register days the books have: the same days the poster reads
  # (SettleUp.register_days), on days that are settled.
  def self.posted(organization)
    SettleUp.register_days(organization)
            .joins("JOIN settlement_days ON settlement_days.organization_id = register_days.organization_id " \
                   "AND settlement_days.date = register_days.business_date AND settlement_days.status = 'settled'")
  end

  def self.owed_total_cents(organization)
    by_integration = posted(organization).group(:integration_id).sum(:tax_cents)
    return 0 if by_integration.empty?

    bringing = Integration.where(id: by_integration.keys).select { |integration| integration.brings?("tax") }.map(&:id)
    by_integration.slice(*bringing).values.sum
  end

  def self.rows(organization, from:, to:)
    posted(organization).where(business_date: from.to_date..to.to_date).includes(:integration, :location).to_a
                        .select { |day| day.integration.brings?("tax") }
                        .group_by(&:location_name).map do |name, days|
      Row.new(name: name, days: days.size, sales_cents: days.sum(&:sales_cents), tax_cents: days.sum(&:tax_cents))
    end.reject { |row| row.tax_cents.zero? }.sort_by(&:name)
  end
end
