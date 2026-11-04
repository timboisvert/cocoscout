# A production's description, and the ticketing words that override it (the
# production's ticket page and each date's), are rich text now: the same Trix
# editor as notes and documents, wherever any of them is written. The plain
# text they held becomes a rich text body, line breaks kept.
class ProductionDescriptionsToRichText < ActiveRecord::Migration[8.1]
  TABLES = { "productions" => "Production", "production_ticketings" => "ProductionTicketing",
             "ticket_listings" => "TicketListing" }.freeze

  def up
    TABLES.each do |table, record_type|
      select_rows("SELECT id, description FROM #{table} WHERE description IS NOT NULL AND btrim(description) <> ''").each do |id, text|
        execute <<~SQL
          INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
          VALUES ('description', #{quote(html_for(text))}, '#{record_type}', #{id.to_i}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
      remove_column table, :description
    end
  end

  def down
    TABLES.each do |table, record_type|
      add_column table, :description, :text
      select_rows("SELECT record_id, body FROM action_text_rich_texts WHERE name = 'description' AND record_type = '#{record_type}'").each do |id, html|
        execute "UPDATE #{table} SET description = #{quote(plain_for(html))} WHERE id = #{id.to_i}"
      end
      execute "DELETE FROM action_text_rich_texts WHERE name = 'description' AND record_type = '#{record_type}'"
    end
  end

  private

  # Plain text the way Trix would have typed it: one block, a <br> per line.
  def html_for(text)
    lines = text.strip.gsub("\r\n", "\n").split("\n").map { |line| ERB::Util.html_escape(line) }
    "<div>#{lines.join('<br>')}</div>"
  end

  def plain_for(html)
    ActionText::Content.new(html.to_s).to_plain_text
  end
end
