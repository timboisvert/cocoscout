# frozen_string_literal: true

require "builder"

# Streaming sitemap controller. No `sitemap_generator` gem; just an
# XML builder cached aggressively in Solid Cache and bumped on Mic save.
module Mics
  class SitemapsController < BaseController
    # Top-level sitemap index: one entry per hub + per-city sitemap.
    def index
      response.set_header("Content-Type", "application/xml; charset=utf-8")

      city_pairs = Mic.active.joins(:venue)
                      .pluck(Arel.sql("venues.city"), Arel.sql("venues.state"))
                      .uniq

      xml = ::Builder::XmlMarkup.new(target: response.stream, indent: 2)
      xml.instruct!(:xml, version: "1.0", encoding: "UTF-8")
      xml.sitemapindex(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
        city_pairs.each do |city, state|
          slug = "#{city.parameterize}-#{state.downcase}"
          xml.sitemap do
            xml.loc mics_sitemap_city_url(slug)
            xml.lastmod Time.current.utc.iso8601
          end
        end
      end
    ensure
      response.stream.close
    end

    # Per-city sitemap: the city page + each Mic in that city.
    def city
      response.set_header("Content-Type", "application/xml; charset=utf-8")

      city, state = city_state_from_slug(params[:city_slug])
      mics = if city && state
        Mic.in_city(city, state).active.includes(:venue)
      else
        Mic.none
      end

      xml = ::Builder::XmlMarkup.new(target: response.stream, indent: 2)
      xml.instruct!(:xml, version: "1.0", encoding: "UTF-8")
      xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
        if city && state && mics.any?
          xml.url do
            xml.loc mics_city_url(params[:city_slug])
            xml.changefreq "daily"
            xml.priority "0.8"
          end
        end

        mics.find_each do |mic|
          xml.url do
            xml.loc mics_detail_url(mic.slug)
            xml.lastmod(mic.updated_at.utc.iso8601)
            xml.changefreq "weekly"
            xml.priority "0.6"
          end
        end
      end
    ensure
      response.stream.close
    end
  end
end
