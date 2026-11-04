# frozen_string_literal: true

# Reads Square into RegisterDays (plan §9.3): for each location that is
# ours, the completed orders and payments over a span, grouped into
# business days by the organization's Settle up setting (a 12:15 am round
# is Friday's). Nothing posts to the books here; the day's worksheet shows
# it and settling the day posts it.
#
#   SquareSync.pull!(integration, from: Date.yesterday, to: Date.current, trigger: "morning")
class SquareSync
  Totals = Struct.new(:sales, :tips, :tax, :refunds, :fees, :orders) do
    def initialize = super(Hash.new(0), 0, 0, 0, 0, 0)
    def net = sales.values.sum + tax + tips - refunds - fees
  end

  def self.pull!(integration, from:, to:, trigger: "manual")
    new(integration).pull!(from: from, to: to, trigger: trigger)
  end

  # Fresh locations and categories from Square, for the settings page.
  def self.refresh_catalog!(integration)
    new(integration).refresh_catalog!
  end

  def initialize(integration)
    @integration = integration
    @organization = integration.organization
  end

  def api
    @api ||= SquareApi.new(fresh_access_token)
  end

  def refresh_catalog!
    locations = api.locations.map { |l| { "id" => l["id"], "name" => l["name"], "address" => l.dig("address", "address_line_1"), "status" => l["status"] } }
    categories = api.catalog.select { |o| o["type"] == "CATEGORY" }.map { |c| { "id" => c["id"], "name" => c.dig("category_data", "name") } }
    known = @integration.external_categories.index_by { |c| c["id"] }
    categories.each { |c| c["first_seen_on"] = known.dig(c["id"], "first_seen_on") || Date.current.iso8601 }
    settings = @integration.settings.merge("locations" => locations, "categories" => categories)
    settings["merchant_name"] ||= api.merchant["business_name"]
    @integration.update!(settings: settings)
    @integration
  end

  def pull!(from:, to:, trigger:)
    pull = @integration.register_pulls.create!(trigger: trigger, from_date: from, to_date: to, started_at: Time.current)
    refresh_catalog! if @integration.external_locations.empty? || @integration.external_categories.empty? || trigger == "manual"
    categories = catalog_categories
    orders_seen = 0

    @integration.external_locations.each do |loc|
      next if @integration.skipped_location?(loc["id"])

      window = SettlementDay.window(@organization, from).begin..SettlementDay.window(@organization, to).end
      days = Hash.new { |h, k| h[k] = Totals.new }
      api.orders(loc["id"], from: window.begin, to: window.end).each do |order|
        date = SettlementDay.day_for(@organization, Time.zone.parse(order["closed_at"] || order["created_at"]))
        next unless (from..to).cover?(date)

        totals = days[date]
        # A refund is an order of its own at Square: no lines, a return.
        if order["line_items"].blank? && order["returns"].present?
          totals.refunds += money(order.dig("return_amounts", "total_money"))
          next
        end

        totals.orders += 1
        orders_seen += 1
        Array(order["line_items"]).each do |line|
          cents = money(line["gross_sales_money"]) - money(line["total_discount_money"])
          totals.sales[@integration.our_category(categories[line["catalog_object_id"]])] += cents
        end
        totals.tax += money(order["total_tax_money"])
        totals.tips += money(order["total_tip_money"])
        totals.refunds += money(order.dig("return_amounts", "total_money"))
      end
      api.payments(loc["id"], from: window.begin, to: window.end).each do |payment|
        date = SettlementDay.day_for(@organization, Time.zone.parse(payment["created_at"]))
        next unless (from..to).cover?(date)

        days[date].fees += Array(payment["processing_fee"]).sum { |f| money(f["amount_money"]) }
      end

      (from..to).each do |date|
        totals = days[date]
        # Not through the association: a has_many autosaves what it built
        # when the integration saves, and a quiet day must leave no row.
        day = RegisterDay.find_or_initialize_by(integration: @integration, external_location_id: loc["id"], business_date: date)
        day.assign_attributes(organization: @organization, location_id: @integration.our_location_id(loc["id"]),
                              sales_by_category: totals.sales.transform_values(&:to_i), gross_cents: totals.sales.values.sum,
                              tips_cents: totals.tips, tax_cents: totals.tax, refunds_cents: totals.refunds, fees_cents: totals.fees,
                              net_cents: totals.net, orders_count: totals.orders, pulled_at: Time.current)
        day.save! if day.any? || day.persisted?
      end
    end

    pull.update!(status: "done", orders_count: orders_seen, finished_at: Time.current)
    @integration.record_success!
    pull
  rescue StandardError => e
    pull&.update!(status: "failed", error: e.message, finished_at: Time.current)
    @integration.record_error!(e.message)
    raise if Rails.env.test? && !e.is_a?(SquareApi::Error)

    pull
  end

  private

  # catalog variation id → category id (an order line names the variation).
  def catalog_categories
    objects = api.catalog
    items = objects.select { |o| o["type"] == "ITEM" }
    map = {}
    items.each do |item|
      category = item.dig("item_data", "reporting_category", "id") || item.dig("item_data", "category_id") ||
                 Array(item.dig("item_data", "categories")).first&.dig("id")
      map[item["id"]] = category
      Array(item.dig("item_data", "variations")).each { |v| map[v["id"]] = category }
    end
    map
  end

  def money(hash)
    hash.is_a?(Hash) ? hash["amount"].to_i : 0
  end

  # Square's access tokens last 30 days; refresh when a week is left.
  def fresh_access_token
    expires = @integration.token_expires_at
    if @integration.refresh_token.present? && (expires.nil? || expires < 7.days.from_now)
      fresh = SquareApi.refresh(@integration.refresh_token)
      @integration.update!(tokens: @integration.tokens.merge("access_token" => fresh["access_token"], "refresh_token" => fresh["refresh_token"] || @integration.refresh_token,
                                                             "expires_at" => fresh["expires_at"]))
    end
    @integration.access_token
  end
end
