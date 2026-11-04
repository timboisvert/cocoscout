# frozen_string_literal: true

# Nights at the bar for development (plan §9.3), two ways:
#
#   square:sandbox_orders   rings up a night on Square's sandbox, order by
#     order, so a pull reads it the way it will read a real night. It needs
#     the sandbox seller's own access token, the one on the Credentials page
#     of Square's Developer Console, because that token can write; the OAuth
#     token CocoScout holds is read only. Square stamps each order with the
#     moment it is paid and cannot backdate, so the night lands on today.
#
#       SQUARE_SANDBOX_ACCESS_TOKEN=... bin/rails square:sandbox_orders NIGHT=friday
#
#   square:dev_register_days   fills past weeks with Thursday-to-Sunday nights
#     as register days on the connected Square integration, no API, so Settle
#     up has something to show. Development only.
#
#       bin/rails square:dev_register_days WEEKS=10
#
# A Thursday or a Sunday is about $300, a Friday or a Saturday about $1,000,
# from $3 candy to $16 cocktails.
namespace :square do
  desc "Ring up a night on the Square sandbox: NIGHT=thursday|friday|saturday|sunday (or TARGET=dollars), tips, tax and a refund or two"
  task sandbox_orders: :environment do
    abort "Only on the sandbox: set SQUARE_ENVIRONMENT=sandbox." unless SquareApi.sandbox?
    token = ENV["SQUARE_SANDBOX_ACCESS_TOKEN"].presence
    abort "Set SQUARE_SANDBOX_ACCESS_TOKEN to the sandbox seller's access token (Developer Console, Credentials page)." unless token

    night = BarNight.new(target_cents: BarNight.target_for(ENV["NIGHT"], ENV["TARGET"]))
    square = SquareSandboxSeller.new(token)
    location_id = ENV["SQUARE_LOCATION_ID"].presence || square.get("/v2/locations").fetch("locations").first.fetch("id")
    variations = square.ensure_catalog!
    puts "Location #{location_id}; catalog of #{variations.size} items; ringing up about $#{night.target_cents / 100} in #{night.orders.size} orders"

    payments = night.orders.map.with_index(1) do |round, n|
      order = square.post("/v2/orders", idempotency_key: SecureRandom.uuid,
                          order: { location_id: location_id,
                                   line_items: round[:lines].map { |name, qty, _| { catalog_object_id: variations.fetch(name), quantity: qty.to_s } },
                                   taxes: [ { uid: "sales-tax", name: "Sales tax", percentage: BarNight::TAX_PERCENT, scope: "ORDER" } ] }).fetch("order")
      total = order.dig("total_money", "amount")
      payment = square.post("/v2/payments", idempotency_key: SecureRandom.uuid, source_id: "cnon:card-nonce-ok", order_id: order["id"],
                                            location_id: location_id, amount_money: { amount: total, currency: "USD" },
                                            tip_money: { amount: round[:tip], currency: "USD" }).fetch("payment")
      puts format("%3d. %-42s $%7.2f%s", n, round[:lines].map { |name, qty, _| "#{qty} #{name}" }.join(", "), total / 100.0, round[:tip].positive? ? format(" + $%.2f tip", round[:tip] / 100.0) : "")
      [ payment, round ]
    end

    night.refunds(payments).each do |payment, cents, reason|
      refund = square.post("/v2/refunds", idempotency_key: SecureRandom.uuid, payment_id: payment["id"],
                                          amount_money: { amount: cents, currency: "USD" }, reason: reason)
      puts format("Refund $%.2f (%s): %s", cents / 100.0, reason, refund.dig("refund", "status"))
    end
    puts "Done: $#{'%.2f' % (night.sales_cents / 100.0)} sold, $#{'%.2f' % (night.tips_cents / 100.0)} in tips. Pull now on the Square page reads it into today's register day."
  end

  desc "Development only: fill past weeks with Thursday-to-Sunday nights as register days on the connected Square integration (WEEKS=10)"
  task dev_register_days: :environment do
    abort "Development only." unless Rails.env.development?
    integration = Integration.connected.square.includes(:organization).find_by(organization_id: ENV["ORG"].presence) || Integration.connected.square.first
    abort "Connect Square first (Organization settings → Integrations)." unless integration
    location = integration.external_locations.find { |l| integration.our_location_id(l["id"]) } || integration.external_locations.first
    abort "No Square location on the integration yet; Pull now reads them." unless location

    weeks = ENV.fetch("WEEKS", "10").to_i
    organization = integration.organization
    today = SettlementDay.day_for(organization, Time.current)
    # The last 7 days stay clear: Pull now re-reads them from Square and would empty them.
    dates = ((today - weeks * 7)...(today - 7)).select { |d| d.thursday? || d.friday? || d.saturday? || d.sunday? }
    made = 0
    dates.each do |date|
      night = BarNight.new(target_cents: BarNight.target_for(date.strftime("%A").downcase, nil), seed: date.jd)
      day = RegisterDay.find_or_initialize_by(integration: integration, external_location_id: location["id"], business_date: date)
      next if day.persisted? && day.any? && ENV["REPLACE"].blank?

      day.assign_attributes(organization: organization, location_id: integration.our_location_id(location["id"]),
                            sales_by_category: night.sales_by_category, gross_cents: night.sales_cents, tips_cents: night.tips_cents,
                            tax_cents: night.tax_cents, refunds_cents: night.refund_cents, fees_cents: night.fee_cents,
                            net_cents: night.sales_cents + night.tax_cents + night.tips_cents - night.refund_cents - night.fee_cents,
                            orders_count: night.orders.size, pulled_at: date.in_time_zone.change(hour: 5), tips_by_time: night.tips_by_time(date))
      day.save!
      made += 1
    end
    puts "#{made} register days written for #{organization.name}, #{dates.first} to #{dates.last} (REPLACE=1 rewrites days already there)."
  end
end

# One night's orders at the bar, the same whether rung up on the sandbox or
# summed straight into a register day.
class BarNight
  TAX_PERCENT = "10.25"
  # name => [category, cents, weight]
  MENU = {
    "Domestic beer" => [ "Bar", 600, 22 ], "Craft beer" => [ "Bar", 800, 18 ], "Hard seltzer" => [ "Bar", 700, 8 ],
    "House red" => [ "Bar", 900, 8 ], "House white" => [ "Bar", 900, 7 ], "Well drink" => [ "Bar", 1_200, 10 ],
    "Cocktail" => [ "Bar", 1_500, 9 ], "Signature cocktail" => [ "Bar", 1_600, 6 ], "Soda" => [ "Bar", 300, 5 ],
    "Candy" => [ "Snacks", 300, 7 ], "Chips" => [ "Snacks", 300, 4 ],
    "T-shirt" => [ "Merch", 2_500, 1 ], "Sticker" => [ "Merch", 400, 2 ]
  }.freeze
  OUR_CATEGORY = { "Bar" => "bar", "Snacks" => "food", "Merch" => "merchandise" }.freeze
  NIGHTS = { "thursday" => 30_000, "friday" => 100_000, "saturday" => 100_000, "sunday" => 30_000 }.freeze

  attr_reader :target_cents, :orders

  def self.target_for(night, dollars)
    return dollars.to_i * 100 if dollars.present?

    NIGHTS.fetch(night.to_s.downcase.presence || "friday") { abort "NIGHT is thursday, friday, saturday or sunday." }
  end

  def initialize(target_cents:, seed: nil)
    @target_cents = target_cents
    @random = seed ? Random.new(seed) : Random.new
    @orders = []
    @orders << ring_one while sales_cents < @target_cents * @random.rand(0.85..1.15)
  end

  def sales_cents = @orders.sum { |o| o[:lines].sum { |_, qty, cents| qty * cents } }
  def tips_cents = @orders.sum { |o| o[:tip] }
  def tax_cents = @orders.sum { |o| (o[:lines].sum { |_, qty, cents| qty * cents } * TAX_PERCENT.to_f / 100).round }
  def fee_cents = @orders.sum { |o| ((o[:lines].sum { |_, qty, cents| qty * cents } + o[:tip]) * 0.026).round + 10 }

  def sales_by_category
    @orders.each_with_object(Hash.new(0)) do |o, sums|
      o[:lines].each { |name, qty, cents| sums[OUR_CATEGORY.fetch(MENU[name][0])] += qty * cents }
    end
  end

  # A refund or two on a busy night: one drink sent back.
  def refunds(paid_rounds)
    count = (sales_cents / 40_000.0).round
    paid_rounds.select { |_, round| round[:lines].size == 1 }.sample(count, random: @random).map do |payment, round|
      [ payment, round[:lines][0][2], [ "Sent back", "Wrong drink", "Charged twice" ].sample(random: @random) ]
    end
  end

  def refund_cents = refunds(@orders.map { |o| [ nil, o ] }).sum { |_, cents, _| cents }

  # The night's tips by quarter hour, the way a Square pull keeps them
  # (§9.14): doors at 6, busiest from 8 to 11, last round around half past
  # midnight. Drawn after the orders, so the orders stay the same.
  def tips_by_time(date)
    evening = date.in_time_zone
    by_time = Hash.new { |h, k| h[k] = { "cents" => 0, "orders" => 0 } }
    @orders.each do |order|
      hour = weighted([ 18, 19, 19, 20, 20, 20, 21, 21, 21, 22, 22, 22, 23, 23, 24 ])
      rang_at = evening.change(hour: hour % 24, min: @random.rand(60)) + (hour >= 24 ? 1.day : 0)
      quarter = by_time[SquareSync.quarter_key(rang_at)]
      quarter["cents"] += order[:tip]
      quarter["orders"] += 1
    end
    by_time.sort.to_h
  end

  private

  def ring_one
    lines = Array.new(weighted([ 1, 1, 1, 1, 2, 2, 3 ])) { [ pick, weighted([ 1, 1, 1, 1, 2 ]) ] }
    lines = lines.group_by(&:first).map { |name, rows| [ name, rows.sum(&:last), MENU[name][1] ] }
    subtotal = lines.sum { |_, qty, cents| qty * cents }
    tip = @random.rand < 0.65 ? ((subtotal * @random.rand(0.15..0.25)) / 100.0).ceil * 100 : 0
    { lines: lines, tip: tip }
  end

  def pick
    weights = MENU.map { |name, (_, _, weight)| [ name, weight ] }
    roll = @random.rand(weights.sum(&:last))
    weights.each { |name, weight| return name if (roll -= weight).negative? }
  end

  def weighted(options) = options.sample(random: @random)
end

# The sandbox seller's side of the API: the few writes the task needs.
class SquareSandboxSeller
  def initialize(token)
    @token = token
  end

  # Item name → variation id, creating the categories and items that are
  # not there yet, so running the task twice does not double the catalog.
  def ensure_catalog!
    existing = get("/v2/catalog/list?types=ITEM").fetch("objects", [])
    found = existing.to_h { |o| [ o.dig("item_data", "name"), o.dig("item_data", "variations", 0, "id") ] }
    missing = BarNight::MENU.reject { |name, _| found[name] }
    return found.slice(*BarNight::MENU.keys) if missing.empty?

    categories = get("/v2/catalog/list?types=CATEGORY").fetch("objects", []).to_h { |o| [ o.dig("category_data", "name"), o["id"] ] }
    objects = missing.map { |_, (category, _, _)| category }.uniq.reject { |c| categories[c] }.map do |category|
      { type: "CATEGORY", id: "##{category.parameterize}", present_at_all_locations: true, category_data: { name: category } }
    end
    objects += missing.map do |name, (category, cents, _)|
      cat_id = categories[category] || "##{category.parameterize}"
      item_id = "##{name.parameterize}"
      { type: "ITEM", id: item_id, present_at_all_locations: true,
        item_data: { name: name, categories: [ { id: cat_id } ], reporting_category: { id: cat_id },
                     variations: [ { type: "ITEM_VARIATION", id: "#{item_id}-v", present_at_all_locations: true,
                                     item_variation_data: { item_id: item_id, name: "Regular", pricing_type: "FIXED_PRICING", price_money: { amount: cents, currency: "USD" } } } ] } }
    end
    result = post("/v2/catalog/batch-upsert", idempotency_key: SecureRandom.uuid, batches: [ { objects: objects } ])
    result.fetch("objects", []).each do |o|
      found[o.dig("item_data", "name")] = o.dig("item_data", "variations", 0, "id") if o["type"] == "ITEM"
    end
    found.slice(*BarNight::MENU.keys)
  end

  def get(path) = perform(Net::HTTP::Get.new(path, headers))

  def post(path, body)
    request = Net::HTTP::Post.new(path, headers)
    request.body = body.to_json
    perform(request)
  end

  private

  def headers
    { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json", "Square-Version" => SquareApi::VERSION }
  end

  def perform(request)
    http = Net::HTTP.new(SquareApi.host, 443)
    http.use_ssl = true
    response = http.request(request)
    body = response.body.present? ? JSON.parse(response.body) : {}
    unless response.is_a?(Net::HTTPSuccess)
      detail = Array(body["errors"]).map { |e| "#{e['code']}: #{e['detail']}" }.join("; ")
      abort "Square answered #{response.code} on #{request.path}: #{detail.presence || body}"
    end
    body
  end
end
