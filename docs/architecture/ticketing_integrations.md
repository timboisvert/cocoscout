# Ticketing Integrations Architecture

## Executive Summary

CocoScout needs to integrate with multiple third-party ticketing platforms (Ticket Tailor, Seat Engine, Wix, EventBrite, etc.) to sync ticket sales, production information, and pricing data. This document outlines the architecture for a flexible, provider-agnostic integration system.

**Key Design Principles:**
1. **Provider Abstraction** - Common interface for all ticketing platforms
2. **Production-Level Configuration** - Different productions can use different ticketing systems
3. **Read-Only Sync** - Pull ticket sales data from external platforms (write support deferred to future)
4. **Targeted Integration Points** - No separate "Integrations" menu; integrate where contextually relevant
5. **Resilient Sync** - Handle API failures, rate limits, and data conflicts gracefully

**Scope Decisions:**
- **Sync Direction**: Read-only for initial implementation (pull sales data in)
- **Fee Handling**: Import platform fees directly into `ShowFinancials.ticket_fees`
- **Historical Data**: Sync recent/upcoming shows only (not full history)
- **Seat Engine**: Defer API research until customer requests it

---

## Provider Capability Matrix

Based on API documentation research (January 2026):

| Capability | Ticket Tailor | Eventbrite | Wix Events | Seat Engine |
|------------|---------------|------------|------------|-------------|
| **Authentication** | API Key (Basic Auth) | OAuth 2.0 | OAuth 2.0 / API Key | API Key |
| **Read Events** | ✅ Full | ✅ Full | ✅ Full | ✅ Limited |
| **Read Sales/Attendees** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Unknown |
| **Read Pricing** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Unknown |
| **Write Events** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Unknown |
| **Webhooks** | ✅ order.created | ✅ Multiple | ✅ Multiple | ❓ Research |
| **Recurring Events** | ✅ Event Series | ✅ Series | ✅ Supported | ✅ Supported |
| **Reserved Seating** | ✅ Native | ⚠️ Via seats.io | ❌ Basic | ✅ Native |
| **Promo Codes** | ✅ Full | ✅ Full | ✅ Full | ✅ Supported |
| **Multi-Currency** | ✅ ISO 4217 | ✅ Per event | ✅ Per site | ⚠️ Unknown |
| **API Maturity** | ✅ Production | ✅ v3 Stable | ✅ v3 Current | ⚠️ Research |

### Provider-Specific Notes

**Ticket Tailor** (Recommended First Implementation)
- API URL: `https://api.tickettailor.com/v1`
- Auth: API key as Basic Auth username, empty password
- Currencies in cents (multiply by 100)
- TLS 1.2+ required
- API keys scoped per "box office" (account)
- 1 credit charged per API-issued ticket
- [API Docs](https://developers.tickettailor.com/)

**Eventbrite**
- API URL: `https://www.eventbriteapi.com/v3`
- Auth: OAuth 2.0 with Bearer token
- Mature, well-documented API
- Excellent webhook support
- Requires API key approval process
- [API Docs](https://www.eventbrite.com/platform/api)

**Wix Events**
- API URL: REST API via `dev.wix.com`
- Auth: OAuth 2.0 or API Key
- Three registration types: Ticketing, RSVP, External
- 2.5% Wix service fee on tickets
- Requires Wix Events app installed on site
- [API Docs](https://dev.wix.com/docs/api-reference/business-solutions/events/introduction)

**Seat Engine**
- Integration details require direct research
- Known: Open API, Zapier/MailChimp integrations, Stripe/PayPal payouts
- Target: Comedy clubs, theaters, small venues
- Has check-in app with real-time sync
- [Website](https://www.seatengine.com/)

### Implementation Priority

1. **Ticket Tailor** - Your own company uses it, simpler API key auth
2. **Eventbrite** - Industry standard, excellent docs
3. **Seat Engine** - Customer request, research API first
4. **Wix Events** - Customer request, full-featured API

---

## Database Schema

### Core Models

```ruby
# Migration: create_ticketing_providers
class CreateTicketingProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_providers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :provider_type, null: false  # eventbrite, ticket_tailor, seat_engine, wix
      t.string :name, null: false           # User-friendly name: "Our Eventbrite Account"

      # OAuth/API credentials (encrypted)
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext
      t.datetime :token_expires_at
      t.string :api_key_ciphertext          # For API key-based auth

      # Provider account info
      t.string :provider_account_id         # Their account ID in the external system
      t.string :provider_account_name       # Display name from provider

      # Sync configuration (read_only for now, extensible for future write support)
      t.boolean :auto_sync_enabled, default: true
      t.integer :sync_interval_minutes, default: 15

      # Status tracking
      t.datetime :last_synced_at
      t.string :last_sync_status            # success, partial, failed
      t.text :last_sync_error
      t.integer :consecutive_failures, default: 0

      t.timestamps
    end

    add_index :ticketing_providers, [:organization_id, :provider_type]
    add_index :ticketing_providers, :provider_account_id
  end
end
```

```ruby
# Migration: create_ticketing_production_links
# Links a Production to a ticketing provider's event/series
class CreateTicketingProductionLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_production_links do |t|
      t.references :production, null: false, foreign_key: true
      t.references :ticketing_provider, null: false, foreign_key: true

      # External identifiers
      t.string :provider_event_id           # Their event/series ID
      t.string :provider_event_name         # Name from provider
      t.string :provider_event_url          # Link to event in provider dashboard

      # Sync settings
      t.boolean :sync_ticket_sales, default: true
      t.boolean :sync_enabled, default: true

      # Mapping configuration
      t.jsonb :field_mappings, default: {}  # Custom field mappings
      t.jsonb :ticket_type_mappings, default: {}  # Map provider ticket types to our concepts

      # Status
      t.datetime :last_synced_at
      t.string :last_sync_hash              # For change detection

      t.timestamps
    end

    add_index :ticketing_production_links, [:production_id, :ticketing_provider_id],
              unique: true, name: 'idx_prod_link_unique'
    add_index :ticketing_production_links, :provider_event_id
  end
end
```

```ruby
# Migration: create_ticketing_show_links
# Links individual Shows to specific ticketed events
class CreateTicketingShowLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_show_links do |t|
      t.references :show, null: false, foreign_key: true
      t.references :ticketing_production_link, null: false, foreign_key: true

      # External identifiers
      t.string :provider_occurrence_id      # Their event occurrence/date ID
      t.string :provider_ticket_page_url    # Public ticket purchase URL

      # Cached ticket data (updated on sync)
      t.integer :tickets_sold, default: 0
      t.integer :tickets_available
      t.integer :tickets_capacity
      t.decimal :gross_revenue, precision: 10, scale: 2
      t.decimal :net_revenue, precision: 10, scale: 2
      t.jsonb :ticket_breakdown, default: []  # Per-tier breakdown

      # Status
      t.datetime :provider_updated_at       # When provider last reported changes
      t.datetime :last_synced_at
      t.string :last_sync_hash
      t.string :sync_status                 # synced, pending, conflict, error
      t.text :sync_notes

      t.timestamps
    end

    add_index :ticketing_show_links, :provider_occurrence_id
    add_index :ticketing_show_links, [:show_id, :ticketing_production_link_id],
              unique: true, name: 'idx_show_link_unique'
  end
end
```

```ruby
# Migration: create_ticketing_sync_logs
# Audit trail for all sync operations
class CreateTicketingSyncLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_sync_logs do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.references :ticketing_production_link, foreign_key: true
      t.references :user, foreign_key: true  # nil for automated syncs

      t.string :sync_type, null: false      # full, incremental, manual, webhook
      t.string :direction, null: false      # inbound, outbound
      t.string :status, null: false         # started, success, partial, failed

      t.integer :records_processed, default: 0
      t.integer :records_created, default: 0
      t.integer :records_updated, default: 0
      t.integer :records_failed, default: 0

      t.jsonb :details, default: {}         # Provider-specific details
      t.text :error_message
      t.text :error_backtrace

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ticketing_sync_logs, [:ticketing_provider_id, :created_at]
    add_index :ticketing_sync_logs, :status
  end
end
```

### Model Relationships

```ruby
# app/models/ticketing_provider.rb
class TicketingProvider < ApplicationRecord
  belongs_to :organization
  has_many :ticketing_production_links, dependent: :destroy
  has_many :productions, through: :ticketing_production_links
  has_many :ticketing_sync_logs, dependent: :destroy

  encrypts :access_token_ciphertext
  encrypts :refresh_token_ciphertext
  encrypts :api_key_ciphertext

  enum :provider_type, {
    eventbrite: 'eventbrite',
    ticket_tailor: 'ticket_tailor',
    seat_engine: 'seat_engine',
    wix: 'wix',
    square: 'square',
    ticketmaster: 'ticketmaster'
  }

  validates :provider_type, presence: true
  validates :name, presence: true

  def service
    @service ||= Ticketing::ServiceFactory.build(self)
  end

  def needs_token_refresh?
    token_expires_at.present? && token_expires_at < 5.minutes.from_now
  end

  def mark_sync_success!
    update!(
      last_synced_at: Time.current,
      last_sync_status: 'success',
      last_sync_error: nil,
      consecutive_failures: 0
    )
  end

  def mark_sync_failure!(error)
    update!(
      last_synced_at: Time.current,
      last_sync_status: 'failed',
      last_sync_error: error.to_s,
      consecutive_failures: consecutive_failures + 1
    )
  end
end
```

```ruby
# app/models/ticketing_production_link.rb
class TicketingProductionLink < ApplicationRecord
  belongs_to :production
  belongs_to :ticketing_provider
  has_many :ticketing_show_links, dependent: :destroy
  has_many :shows, through: :ticketing_show_links

  validates :provider_event_id, presence: true
  validates :production_id, uniqueness: { scope: :ticketing_provider_id }

  def sync_enabled?
    sync_enabled && ticketing_provider.auto_sync_enabled?
  end
end
```

```ruby
# app/models/ticketing_show_link.rb
class TicketingShowLink < ApplicationRecord
  belongs_to :show
  belongs_to :ticketing_production_link
  has_one :ticketing_provider, through: :ticketing_production_link
  has_one :production, through: :ticketing_production_link

  after_save :update_show_financials, if: :ticket_data_changed?

  def ticket_data_changed?
    saved_change_to_tickets_sold? ||
    saved_change_to_gross_revenue? ||
    saved_change_to_net_revenue?
  end

  def update_show_financials
    return unless show.show_financials

    # Import ticket data and platform fees directly into ShowFinancials
    show.show_financials.update!(
      ticket_count: tickets_sold,
      ticket_revenue: net_revenue || gross_revenue,
      ticket_fees: build_ticket_fees
    )
  end

  def build_ticket_fees
    # Convert provider fee breakdown into ShowFinancials.ticket_fees format
    return [] if ticket_breakdown.blank?

    ticket_breakdown.map do |tier|
      {
        name: tier['name'] || 'Platform Fee',
        flat_per_ticket: tier['fee_per_ticket'],
        percentage: tier['fee_percentage'],
        calculated_fee: tier['total_fees']
      }
    end
  end

  def ticket_page_url
    provider_ticket_page_url.presence ||
      ticketing_provider.service.ticket_page_url_for(self)
  end
end
```

---

## Service Architecture

Following the established CalendarSync pattern:

```
app/services/ticketing/
├── base_service.rb           # Abstract base class
├── service_factory.rb        # Builds correct service for provider type
├── capabilities.rb           # Defines what each provider can do
├── sync_coordinator.rb       # Orchestrates sync operations
│
├── providers/
│   ├── eventbrite_service.rb
│   ├── ticket_tailor_service.rb
│   ├── seat_engine_service.rb
│   ├── wix_service.rb
│   └── square_service.rb
│
├── operations/
│   ├── import_events.rb      # Pull events from provider
│   ├── import_sales.rb       # Pull ticket sales data
│   └── match_shows.rb        # Match provider events to our shows
│
└── webhooks/
    ├── base_handler.rb
    ├── eventbrite_handler.rb
    └── ticket_tailor_handler.rb
```

### Base Service

```ruby
# app/services/ticketing/base_service.rb
module Ticketing
  class BaseService
    attr_reader :provider

    def initialize(provider)
      @provider = provider
    end

    # === Authentication ===

    def self.authorization_url(organization, redirect_uri:)
      raise NotImplementedError
    end

    def self.exchange_code_for_tokens(code, redirect_uri:)
      raise NotImplementedError
    end

    def refresh_token!
      raise NotImplementedError
    end

    # === Capabilities (override in subclasses) ===

    def capabilities
      Capabilities.new(
        read_events: false,
        read_sales: false,
        read_pricing: false,
        write_events: false,
        write_pricing: false,
        webhooks: false,
        real_time_sales: false
      )
    end

    # === Read Operations ===

    def fetch_events(since: nil)
      raise NotImplementedError
    end

    def fetch_event(provider_event_id)
      raise NotImplementedError
    end

    def fetch_occurrences(provider_event_id)
      raise NotImplementedError
    end

    def fetch_sales(provider_event_id, occurrence_id: nil, since: nil)
      raise NotImplementedError
    end

    def fetch_ticket_types(provider_event_id)
      raise NotImplementedError
    end

    # === Write Operations ===

    def create_event(production)
      raise NotImplementedError
    end

    def update_event(production_link)
      raise NotImplementedError
    end

    def create_occurrence(show, production_link)
      raise NotImplementedError
    end

    def update_occurrence(show_link)
      raise NotImplementedError
    end

    # === URL Generation ===

    def dashboard_url
      raise NotImplementedError
    end

    def event_dashboard_url(provider_event_id)
      raise NotImplementedError
    end

    def ticket_page_url_for(show_link)
      raise NotImplementedError
    end

    protected

    def http_get(url, params: {}, headers: {})
      ensure_valid_token!

      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      apply_auth_headers(request)
      headers.each { |k, v| request[k] = v }

      execute_request(uri, request)
    end

    def http_post(url, body:, headers: {})
      ensure_valid_token!

      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.body = body.to_json
      request['Content-Type'] = 'application/json'
      apply_auth_headers(request)
      headers.each { |k, v| request[k] = v }

      execute_request(uri, request)
    end

    def ensure_valid_token!
      refresh_token! if provider.needs_token_refresh?
    end

    def apply_auth_headers(request)
      if provider.access_token_ciphertext.present?
        request['Authorization'] = "Bearer #{provider.access_token_ciphertext}"
      elsif provider.api_key_ciphertext.present?
        # Provider-specific API key handling
        apply_api_key(request)
      end
    end

    def apply_api_key(request)
      # Override in subclass for provider-specific API key format
      request['Authorization'] = "Bearer #{provider.api_key_ciphertext}"
    end

    def execute_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 30

      response = http.request(request)
      handle_response(response)
    end

    def handle_response(response)
      case response.code.to_i
      when 200..299
        JSON.parse(response.body) rescue response.body
      when 401
        raise AuthenticationError, "Authentication failed: #{response.body}"
      when 429
        raise RateLimitError, "Rate limited: #{response.body}"
      else
        raise ApiError, "API error #{response.code}: #{response.body}"
      end
    end

    class AuthenticationError < StandardError; end
    class RateLimitError < StandardError; end
    class ApiError < StandardError; end
  end
end
```

### Capabilities System

```ruby
# app/services/ticketing/capabilities.rb
module Ticketing
  class Capabilities
    FEATURES = %i[
      read_events
      read_sales
      read_pricing
      read_attendees
      write_events
      write_pricing
      webhooks
      real_time_sales
      recurring_events
      reserved_seating
      waitlists
      promo_codes
    ].freeze

    attr_reader(*FEATURES)

    def initialize(**features)
      FEATURES.each do |feature|
        instance_variable_set(:"@#{feature}", features.fetch(feature, false))
      end
    end

    def supports?(feature)
      public_send(feature)
    end

    def to_h
      FEATURES.index_with { |f| public_send(f) }
    end
  end
end
```

### Provider-Specific Services

```ruby
# app/services/ticketing/providers/eventbrite_service.rb
module Ticketing
  module Providers
    class EventbriteService < BaseService
      BASE_URL = 'https://www.eventbriteapi.com/v3'

      def self.authorization_url(organization, redirect_uri:)
        params = {
          response_type: 'code',
          client_id: Rails.application.credentials.dig(:eventbrite, :client_id),
          redirect_uri: redirect_uri
        }
        "https://www.eventbrite.com/oauth/authorize?#{URI.encode_www_form(params)}"
      end

      def self.exchange_code_for_tokens(code, redirect_uri:)
        # OAuth2 token exchange
        uri = URI('https://www.eventbrite.com/oauth/token')
        response = Net::HTTP.post_form(uri, {
          grant_type: 'authorization_code',
          client_id: Rails.application.credentials.dig(:eventbrite, :client_id),
          client_secret: Rails.application.credentials.dig(:eventbrite, :client_secret),
          code: code,
          redirect_uri: redirect_uri
        })

        JSON.parse(response.body)
      end

      def capabilities
        Capabilities.new(
          read_events: true,
          read_sales: true,
          read_pricing: true,
          read_attendees: true,
          write_events: true,
          write_pricing: true,
          webhooks: true,
          real_time_sales: true,  # via webhooks
          recurring_events: true,
          promo_codes: true
        )
      end

      def fetch_events(since: nil)
        params = { status: 'live,started,ended,completed' }
        params[:changed_since] = since.iso8601 if since

        http_get("#{BASE_URL}/users/me/events/", params: params)
      end

      def fetch_sales(provider_event_id, occurrence_id: nil, since: nil)
        params = {}
        params[:changed_since] = since.iso8601 if since

        http_get("#{BASE_URL}/events/#{provider_event_id}/attendees/", params: params)
      end

      def fetch_ticket_types(provider_event_id)
        http_get("#{BASE_URL}/events/#{provider_event_id}/ticket_classes/")
      end

      def dashboard_url
        "https://www.eventbrite.com/organizations/events"
      end

      def event_dashboard_url(provider_event_id)
        "https://www.eventbrite.com/myevent?eid=#{provider_event_id}"
      end

      def ticket_page_url_for(show_link)
        # Eventbrite uses the main event URL for all occurrences
        production_link = show_link.ticketing_production_link
        "https://www.eventbrite.com/e/#{production_link.provider_event_id}"
      end
    end
  end
end
```

```ruby
# app/services/ticketing/providers/ticket_tailor_service.rb
module Ticketing
  module Providers
    class TicketTailorService < BaseService
      BASE_URL = 'https://api.tickettailor.com/v1'

      def capabilities
        Capabilities.new(
          read_events: true,
          read_sales: true,
          read_pricing: true,
          write_events: true,
          write_pricing: true,
          webhooks: true,
          real_time_sales: true,
          recurring_events: true,
          reserved_seating: true,
          waitlists: true,
          promo_codes: true
        )
      end

      def apply_api_key(request)
        # Ticket Tailor uses Basic auth with API key as username
        request.basic_auth(provider.api_key_ciphertext, '')
      end

      def fetch_events(since: nil)
        http_get("#{BASE_URL}/event_series")
      end

      def fetch_occurrences(provider_event_id)
        http_get("#{BASE_URL}/event_series/#{provider_event_id}/events")
      end

      def fetch_sales(provider_event_id, occurrence_id: nil, since: nil)
        path = if occurrence_id
          "#{BASE_URL}/events/#{occurrence_id}/issued_tickets"
        else
          "#{BASE_URL}/event_series/#{provider_event_id}/issued_tickets"
        end

        http_get(path)
      end

      def dashboard_url
        "https://www.tickettailor.com/box-office"
      end

      def event_dashboard_url(provider_event_id)
        "https://www.tickettailor.com/box-office/events/series/#{provider_event_id}"
      end

      def ticket_page_url_for(show_link)
        occurrence_id = show_link.provider_occurrence_id
        "https://www.tickettailor.com/events/#{occurrence_id}"
      end
    end
  end
end
```

### Service Factory

```ruby
# app/services/ticketing/service_factory.rb
module Ticketing
  class ServiceFactory
    PROVIDERS = {
      'eventbrite' => Providers::EventbriteService,
      'ticket_tailor' => Providers::TicketTailorService,
      'seat_engine' => Providers::SeatEngineService,
      'wix' => Providers::WixService,
      'square' => Providers::SquareService
    }.freeze

    def self.build(provider)
      service_class = PROVIDERS[provider.provider_type]
      raise "Unknown provider type: #{provider.provider_type}" unless service_class

      service_class.new(provider)
    end

    def self.available_providers
      PROVIDERS.keys
    end

    def self.provider_display_name(type)
      {
        'eventbrite' => 'Eventbrite',
        'ticket_tailor' => 'Ticket Tailor',
        'seat_engine' => 'Seat Engine',
        'wix' => 'Wix Events',
        'square' => 'Square'
      }[type] || type.titleize
    end
  end
end
```

---

## Sync Strategy (Read-Only)

For organizations that manage ticketing externally and want sales data in CocoScout.
Sales data is pulled from the ticketing platform and imported into `ShowFinancials.ticket_fees`.

```ruby
# app/services/ticketing/operations/import_sales.rb
module Ticketing
  module Operations
    class ImportSales
      def initialize(production_link)
        @production_link = production_link
        @provider = production_link.ticketing_provider
        @service = @provider.service
      end

      def call
        return unless @production_link.sync_enabled?

        sync_log = create_sync_log(:inbound)

        begin
          @production_link.ticketing_show_links.find_each do |show_link|
            sync_show_sales(show_link, sync_log)
          end

          sync_log.update!(status: 'success', completed_at: Time.current)
          @provider.mark_sync_success!
        rescue => e
          sync_log.update!(
            status: 'failed',
            error_message: e.message,
            error_backtrace: e.backtrace&.first(10)&.join("\n"),
            completed_at: Time.current
          )
          @provider.mark_sync_failure!(e)
          raise
        end
      end

      private

      def sync_show_sales(show_link, sync_log)
        return unless show_link.provider_occurrence_id

        sales_data = @service.fetch_sales(
          @production_link.provider_event_id,
          occurrence_id: show_link.provider_occurrence_id,
          since: show_link.last_synced_at
        )

        processed = process_sales_data(sales_data)

        show_link.update!(
          tickets_sold: processed[:total_sold],
          gross_revenue: processed[:gross_revenue],
          net_revenue: processed[:net_revenue],
          ticket_breakdown: processed[:breakdown],
          last_synced_at: Time.current,
          sync_status: 'synced'
        )

        sync_log.increment!(:records_updated)
      end

      def process_sales_data(data)
        # Normalize provider-specific response to common format
        # This is where provider differences get abstracted
        {
          total_sold: data['total'] || data.dig('pagination', 'total') || 0,
          gross_revenue: extract_gross_revenue(data),
          net_revenue: extract_net_revenue(data),
          breakdown: extract_breakdown(data)
        }
      end
    end
  end
end
```

### Event Matching

When connecting a production to an existing ticketing event:

```ruby
# app/services/ticketing/operations/match_shows.rb
module Ticketing
  module Operations
    class MatchShows
      # Attempts to automatically match provider occurrences to our shows
      # based on date/time

      def initialize(production_link)
        @production_link = production_link
      end

      def call
        provider_occurrences = fetch_provider_occurrences
        our_shows = @production_link.production.shows.order(:date_and_time)

        matches = []
        unmatched_shows = []
        unmatched_occurrences = []

        our_shows.each do |show|
          match = find_best_match(show, provider_occurrences)

          if match
            matches << { show: show, occurrence: match }
            provider_occurrences.delete(match)
          else
            unmatched_shows << show
          end
        end

        unmatched_occurrences = provider_occurrences

        {
          matches: matches,
          unmatched_shows: unmatched_shows,
          unmatched_occurrences: unmatched_occurrences
        }
      end

      def apply_matches!(matches)
        matches.each do |match|
          TicketingShowLink.create!(
            show: match[:show],
            ticketing_production_link: @production_link,
            provider_occurrence_id: match[:occurrence]['id'],
            provider_ticket_page_url: match[:occurrence]['url'],
            sync_status: 'pending'
          )
        end
      end

      private

      def find_best_match(show, occurrences)
        occurrences.find do |occ|
          occurrence_time = parse_occurrence_time(occ)
          (show.date_and_time - occurrence_time).abs < 2.hours
        end
      end
    end
  end
end
```

---

## Background Jobs

```ruby
# app/jobs/ticketing_sync_job.rb
class TicketingSyncJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff
  retry_on Ticketing::BaseService::RateLimitError, wait: :polynomially_longer, attempts: 5
  retry_on Ticketing::BaseService::ApiError, wait: 5.minutes, attempts: 3

  # Don't retry auth errors - need user intervention
  discard_on Ticketing::BaseService::AuthenticationError

  def perform(ticketing_provider_id, sync_type: :incremental)
    provider = TicketingProvider.find(ticketing_provider_id)

    return unless provider.auto_sync_enabled?
    return if provider.consecutive_failures >= 5  # Circuit breaker

    Ticketing::SyncCoordinator.new(provider).sync(type: sync_type)
  end
end
```

```ruby
# app/jobs/ticketing_webhook_job.rb
class TicketingWebhookJob < ApplicationJob
  queue_as :default

  def perform(provider_type, payload)
    handler = Ticketing::Webhooks.handler_for(provider_type)
    handler.process(payload)
  end
end
```

### Scheduled Sync

```ruby
# config/recurring.yml (Solid Queue)
production:
  ticketing_sync:
    class: TicketingScheduledSyncJob
    queue: default
    schedule: every 15 minutes
```

```ruby
# app/jobs/ticketing_scheduled_sync_job.rb
class TicketingScheduledSyncJob < ApplicationJob
  queue_as :default

  def perform
    TicketingProvider.where(auto_sync_enabled: true)
                     .where('consecutive_failures < 5')
                     .find_each do |provider|
      next if recently_synced?(provider)

      TicketingSyncJob.perform_later(provider.id)
    end
  end

  private

  def recently_synced?(provider)
    provider.last_synced_at.present? &&
      provider.last_synced_at > provider.sync_interval_minutes.minutes.ago
  end
end
```

---

## Webhook Handling

```ruby
# app/controllers/webhooks/ticketing_controller.rb
module Webhooks
  class TicketingController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!

    def eventbrite
      verify_eventbrite_signature!
      TicketingWebhookJob.perform_later('eventbrite', payload_params)
      head :ok
    end

    def ticket_tailor
      verify_ticket_tailor_signature!
      TicketingWebhookJob.perform_later('ticket_tailor', payload_params)
      head :ok
    end

    private

    def verify_eventbrite_signature!
      # Eventbrite webhook signature verification
    end

    def verify_ticket_tailor_signature!
      # Ticket Tailor webhook signature verification
    end

    def payload_params
      params.permit!.to_h
    end
  end
end
```

```ruby
# config/routes.rb
namespace :webhooks do
  post 'ticketing/eventbrite'
  post 'ticketing/ticket_tailor'
  post 'ticketing/seat_engine'
end
```

---

## Targeted Integration Points (UI)

Rather than a separate "Integrations" menu, ticketing integrations appear contextually:

### 1. Production Settings

Add a "Ticketing" tab within production settings:

```erb
<%# app/views/manage/productions/_ticketing_tab.html.erb %>
<div class="space-y-6">
  <% if @production.ticketing_production_links.any? %>
    <% @production.ticketing_production_links.each do |link| %>
      <%= render 'ticketing_link_card', link: link %>
    <% end %>
  <% else %>
    <div class="text-center py-12">
      <svg class="mx-auto h-12 w-12 text-gray-400">...</svg>
      <h3 class="mt-2 text-sm font-semibold text-gray-900">No ticketing connected</h3>
      <p class="mt-1 text-sm text-gray-500">
        Connect a ticketing platform to sync ticket sales automatically.
      </p>
    </div>
  <% end %>

  <div class="border-t pt-6">
    <h4 class="font-medium text-gray-900 mb-4">Connect Ticketing Platform</h4>
    <%= render 'connect_ticketing_buttons' %>
  </div>
</div>
```

### 2. Show Financials

Show ticketing sync status on the financials page:

```erb
<%# In show financials view %>
<% if @show.ticketing_show_link %>
  <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-4">
    <div class="flex items-center justify-between">
      <div class="flex items-center">
        <%= image_tag provider_logo(@show.ticketing_show_link.ticketing_provider), class: "h-5 w-5 mr-2" %>
        <span class="text-sm text-blue-700">
          Synced from <%= @show.ticketing_show_link.ticketing_provider.name %>
        </span>
      </div>
      <span class="text-xs text-blue-500">
        Last updated <%= time_ago_in_words(@show.ticketing_show_link.last_synced_at) %> ago
      </span>
    </div>

    <% if @show.ticketing_show_link.provider_ticket_page_url %>
      <%= link_to "View in #{provider_name}", @show.ticketing_show_link.provider_ticket_page_url,
                  target: '_blank', class: "text-sm text-blue-600 hover:underline" %>
    <% end %>
  </div>
<% end %>
```

### 3. Organization Settings

Add connected ticketing providers in org settings:

```erb
<%# app/views/manage/organizations/_ticketing_providers.html.erb %>
<div class="bg-white shadow rounded-lg">
  <div class="px-4 py-5 border-b border-gray-200 sm:px-6">
    <h3 class="text-lg font-medium text-gray-900">Connected Ticketing Platforms</h3>
    <p class="mt-1 text-sm text-gray-500">
      Manage your connected ticketing accounts. Each production can use a different platform.
    </p>
  </div>

  <ul class="divide-y divide-gray-200">
    <% @organization.ticketing_providers.each do |provider| %>
      <li class="px-4 py-4 sm:px-6">
        <div class="flex items-center justify-between">
          <div class="flex items-center">
            <%= image_tag provider_logo(provider), class: "h-8 w-8 mr-3" %>
            <div>
              <p class="font-medium text-gray-900"><%= provider.name %></p>
              <p class="text-sm text-gray-500"><%= provider.provider_account_name %></p>
            </div>
          </div>
          <div class="flex items-center space-x-4">
            <span class="<%= sync_status_badge_class(provider) %>">
              <%= sync_status_text(provider) %>
            </span>
            <%= link_to 'Configure', manage_ticketing_provider_path(provider),
                        class: "text-sm text-pink-600 hover:text-pink-800" %>
          </div>
        </div>
      </li>
    <% end %>
  </ul>

  <div class="px-4 py-4 bg-gray-50 rounded-b-lg">
    <%= link_to new_manage_ticketing_provider_path do %>
      <%= render "shared/button", text: "Connect Platform", variant: "secondary", size: "small" %>
    <% end %>
  </div>
</div>
```

### 4. Dashboard Widgets

Show ticket sales summary on production dashboard:

```erb
<%# Widget for production dashboard %>
<div class="bg-white shadow rounded-lg p-6">
  <h4 class="text-sm font-medium text-gray-500 uppercase tracking-wide">Ticket Sales</h4>

  <% if @production.has_ticketing_integration? %>
    <div class="mt-4">
      <p class="text-3xl font-bold text-gray-900">
        <%= number_to_currency(@production.total_ticket_revenue) %>
      </p>
      <p class="text-sm text-gray-500">
        <%= pluralize(@production.total_tickets_sold, 'ticket') %> sold
      </p>
    </div>

    <div class="mt-4 pt-4 border-t">
      <p class="text-xs text-gray-400">
        via <%= @production.ticketing_provider_names.to_sentence %>
      </p>
    </div>
  <% else %>
    <div class="mt-4 text-center py-4">
      <p class="text-sm text-gray-500 mb-3">No ticketing platform connected</p>
      <%= link_to manage_production_ticketing_path(@production), class: "text-sm text-pink-600 hover:text-pink-800" do %>
        Connect ticketing &rarr;
      <% end %>
    </div>
  <% end %>
</div>
```

---

## Provider Implementation Priority

Based on your customer base:

### Phase 1 (Immediate)
1. **Ticket Tailor** - Used by Coco Runs Everything (your own company)
   - API key auth (simpler than OAuth)
   - Full read/write capabilities
   - Good webhook support

### Phase 2 (Next)
2. **Eventbrite** - Industry standard, likely most requested
   - OAuth2 authentication
   - Excellent API documentation
   - Real-time webhooks

### Phase 3 (Following)
3. **Seat Engine** - Used by one customer
   - Research API capabilities
   - May have limited API access

4. **Wix Events** - Used by one customer
   - Wix has decent API
   - OAuth2 flow

### Future
5. **Square** - Growing in events space
6. **Ticketmaster** - Enterprise/larger venues
7. **Brown Paper Tickets** - Community theater popular

---

## Security Considerations

### Credential Storage
- All API keys and tokens encrypted at rest using Rails encryption
- Refresh tokens stored separately from access tokens
- Token rotation on refresh

### Webhook Verification
- Each provider has signature verification
- Replay attack prevention with timestamp checking
- IP allowlisting where supported

### Rate Limiting
- Track API calls per provider
- Implement backoff on rate limit errors
- Circuit breaker pattern (stop after 5 consecutive failures)

### Audit Trail
- Log all sync operations
- Track who initiated manual syncs
- Store error details for debugging

---

## Implementation Roadmap

### Phase 1: Foundation
- [ ] Create database migrations (4 tables)
- [ ] Implement base models with encryption
- [ ] Build `Ticketing::BaseService` with HTTP helpers
- [ ] Create `ServiceFactory`

### Phase 2: Ticket Tailor Integration
- [ ] Implement `TicketTailorService`
- [ ] API key connection flow (no OAuth needed)
- [ ] Create `ImportSales` operation
- [ ] Create `MatchShows` operation
- [ ] Add webhook handler for `order.created`
- [ ] Test with Coco Runs Everything data

### Phase 3: UI Integration
- [ ] Add "Ticketing" tab to production settings
- [ ] Build provider connection flow
- [ ] Show sync status badge on Show Financials
- [ ] Add ticket sales widget to production dashboard

### Phase 4: Eventbrite Integration
- [ ] Implement `EventbriteService`
- [ ] OAuth2 flow with token refresh
- [ ] Webhook handling
- [ ] Test with sample data

### Future (As Requested)
- [ ] Wix Events implementation
- [ ] Seat Engine (pending API research)

---

## Resolved Decisions

1. **Fee Handling**: Import platform fees directly into `ShowFinancials.ticket_fees`
2. **Historical Data**: Sync recent/upcoming shows only (not full history)
3. **Sync Direction**: Read-only for initial implementation
4. **Seat Engine**: Defer API research until customer specifically requests it

## Open Questions

1. **Currency**: Do we need multi-currency support? Some platforms report in different currencies.

2. **Per-Show Override**: Should individual shows be able to opt-out of sync even if production is connected?

3. **Matching Threshold**: When auto-matching shows to provider occurrences, what time tolerance? (Currently 2 hours)
