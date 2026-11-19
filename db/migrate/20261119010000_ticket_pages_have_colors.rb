# frozen_string_literal: true

# Light styling for the box office's landing page and ticket pages (Tim,
# 2026-11-18): a background, a button, a heading, and a text color. Set on the
# box office (ticketing_profiles), and overridden, all four together, by a
# production (production_ticketings) or a date (ticket_listings). Blank is the
# standard look.
class TicketPagesHaveColors < ActiveRecord::Migration[8.1]
  def change
    %i[ticketing_profiles production_ticketings ticket_listings].each do |table|
      add_column table, :page_background_color, :string
      add_column table, :page_button_color, :string
      add_column table, :page_heading_color, :string
      add_column table, :page_text_color, :string
    end
  end
end
