# frozen_string_literal: true

require "rails_helper"

# Every email goes out with a plain-text version beside its HTML, made from
# the HTML at delivery when the mailer didn't write one; the logo stays an
# inline image and attachments stay attached (Tim, 2026-10-12).
RSpec.describe PlainTextAlternativeInterceptor do
  before { ActionMailer::Base.deliveries.clear }

  def sent = ActionMailer::Base.deliveries.last

  it "adds readable text to an HTML-only email, keeping the inline logo" do
    AppMailer.with(template_key: "ticketing_daily_summary", to: "tim@example.com",
                   variables: { "organization_name" => "Stars & Garters", "date_label" => "Sunday, October 11",
                                "tickets_sold" => 8, "ticket_sales" => "$220.00", "yesterday_table" => "<p>No sales that day.</p>",
                                "refunds_table" => "", "settings_url" => "https://www.cocoscout.com/manage/ticketing/settings",
                                "ticketing_url" => "https://www.cocoscout.com/manage/ticketing" }).send_template.deliver_now

    expect(sent.text_part).to be_present
    expect(sent.html_part).to be_present
    text = sent.text_part.decoded
    expect(text).to include("Sunday, October 11", "Stars & Garters")
    expect(text).not_to include("<p>", "<style", "font-family", "{{")
    expect(sent.attachments.map(&:filename)).to include("cocoscout.png")
    expect(sent.attachments.find { |a| a.filename == "cocoscout.png" }).to be_inline
    expect(sent.html_part.decoded).to include("cid:")
  end

  it "leaves an email that already has its own text part alone" do
    message = Mail.new do
      to "tim@example.com"
      text_part { body "Written by hand" }
      html_part { content_type "text/html; charset=UTF-8"; body "<p>Hello</p>" }
    end
    described_class.delivering_email(message)
    expect(message.text_part.decoded).to eq("Written by hand")
  end

  it "keeps a PDF attachment attached" do
    organization = create(:organization, :pro, name: "Stars & Garters")
    statement = OrgStatement.create!(organization: organization, month: Date.new(2026, 9, 1), totals: {})
    statement.pdf.attach(io: StringIO.new("%PDF-1.4 test"), filename: statement.filename, content_type: "application/pdf")
    OrgStatementMailer.statement(statement, to: "tim@example.com", first_name: "Tim").deliver_now

    expect(sent.text_part.decoded).to be_present
    expect(sent.attachments.map(&:filename)).to include(statement.filename, "cocoscout.png")
    expect(sent.attachments.find { |a| a.filename == statement.filename }).not_to be_inline
  end

  it "writes links out, since a text email can't hide them" do
    html = %(<html><head><style>p{color:red}</style></head><body><p>Hi&nbsp;Tim &amp; co</p>) +
           %(<p><a href="https://www.cocoscout.com/my/tickets?x=1&amp;y=2">View your tickets</a></p><ul><li>One</li><li>Two</li></ul></body></html>)
    text = EmailPlainText.from_html(html)
    expect(text).to eq("Hi Tim & co\n\nView your tickets (https://www.cocoscout.com/my/tickets?x=1&y=2)\n\n- One\n- Two")
  end
end
