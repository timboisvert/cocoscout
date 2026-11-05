# frozen_string_literal: true

# A year of CocoScout's costs outside Stripe for the CPA: every confirmed
# bill as a row (CSV), or that file plus every receipt in one zip. Labelled
# CocoScout on every row: Coco Runs Everything has other business that
# isn't in here.
class CompanyExpenseExport
  HEADERS = [ "Part of the company", "Month it's for", "Vendor", "Category", "What", "Bill number", "Bill total", "CocoScout's share (%)",
              "Cost to CocoScout", "Billed on", "Paid on", "Who paid", "Receipt files", "Note" ].freeze

  def self.basename(year) = "CocoScout costs #{year}"

  def self.bills(year)
    CompanyExpense.confirmed.for_year(year).with_attached_documents.order(:period_month, :vendor, :id)
  end

  def self.csv(year)
    require "csv"
    CSV.generate do |csv|
      csv << HEADERS
      bills(year).each do |bill|
        csv << [ "CocoScout", bill.period_month.strftime("%Y-%m"), bill.vendor, bill.category_label, bill.description, bill.bill_number,
                 dollars(bill.bill_total_cents), bill.share_percent.to_d.to_s("F").sub(/\.0\z/, ""), dollars(bill.amount_cents),
                 bill.billed_on&.iso8601, bill.paid_on&.iso8601, bill.paid_by_label,
                 bill.documents.each_with_index.map { |doc, index| file_name(bill, doc, index) }.join("; "), bill.note ]
      end
    end
  end

  # The CSV and every receipt, each named for its month and vendor.
  def self.zip(year)
    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("#{basename(year)}.csv")
      zip.write csv(year)
      bills(year).each do |bill|
        bill.documents.each_with_index do |doc, index|
          zip.put_next_entry("receipts/#{file_name(bill, doc, index)}")
          zip.write doc.download
        end
      end
    end
    buffer.string
  end

  # "2026-01 Amazon 1234567890.pdf", and "... (2).pdf" for a second file.
  def self.file_name(bill, doc, index)
    stem = [ bill.period_month.strftime("%Y-%m"), bill.vendor, bill.bill_number || "bill #{bill.id}" ].join(" ").gsub(%r{[/\\:*?"<>|]}, "-")
    "#{stem}#{" (#{index + 1})" if index.positive?}#{doc.filename.extension_with_delimiter}"
  end

  def self.dollars(cents) = format("%.2f", cents.to_i / 100.0)
end
