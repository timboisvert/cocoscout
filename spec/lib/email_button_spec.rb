# frozen_string_literal: true

require "rails_helper"

# One email button (Tim, 2026-11-09: "if there's not an email button
# standard then there better be one"). The website's primary button, written
# once in EmailButton; every email is passed through it as it goes out; and
# nothing in the code draws a button any other way.
RSpec.describe EmailButton do
  let(:standard) { %(style="#{described_class::STYLE}") }

  it "is the website's primary button" do
    expect(described_class::STYLE).to include("background-color:#ec4899", "color:#ffffff", "font-weight:500", "border-radius:4px", "padding:10px 20px", "font-size:14px")
    expect(described_class.html("Get the app", "https://x.test/a?b=1&c=2"))
      .to eq(%(<a href="https://x.test/a?b=1&amp;c=2" class="button" #{standard}>Get the app</a>))
  end

  it "makes a button drawn any other way the standard one, and leaves plain links alone" do
    drawn = [
      %(<a href="{{sign_url}}" style="display:inline-block;padding:10px 20px;background-color:#ec4899;color:#ffffff;text-decoration:none;border-radius:6px;font-weight:600;">Sign</a>),
      %(<a href="{{inbox_url}}" style="display: inline-block; background-color: #db2777; color: white; padding: 12px 28px; border-radius: 4px; text-decoration: none; font-weight: 600;">Open</a>),
      %(<a style='background:#ec4899;padding:12px 24px;border-radius:8px' href="{{app_url}}" target="_blank">Get the app</a>),
      %(<a class="button" href="https://x.test">Go</a>),
      %(<a class="cta button" style="color: red" href="https://x.test">Go</a>)
    ]
    drawn.each do |html|
      out = described_class.standardize("<p>#{html}</p>")
      expect(out.scan("style=").size).to eq(1), html
      expect(out).to include(standard), html
      expect(out).to include(html[/href="[^"]*"/]), html
    end

    # An organization's own email keeps the organization's colour, on the same button.
    own = described_class.standardize(%(<a href="https://x.test/t" class="button" data-button-color="#0f766e" style="background:#0f766e;padding:8px 16px">Buy tickets</a>))
    expect(own).to include("background-color:#0f766e", "border-radius:4px", "padding:10px 20px", "font-weight:500")
    expect(own).not_to include(described_class::PINK)
    expect(described_class.style(background: "javascript:alert(1)")).to eq(described_class::STYLE)
    expect(described_class.style(background: nil)).to eq(described_class::STYLE)

    plain = %(<p>See <a href="https://x.test">your shifts</a>, or <a href="mailto:a@b.test" style="color: #be185d;">write to us</a>.</p>)
    expect(described_class.standardize(plain)).to eq(plain)
    expect(described_class.standardize(described_class.standardize(drawn.first))).to eq(described_class.standardize(drawn.first))
    expect(described_class.standardize(nil)).to be_nil
  end

  it "reaches every email as it goes out, and keeps the rest of it as it was" do
    mailer = Class.new(ApplicationMailer) do
      def self.name = "ButtonProbeMailer"

      def probe
        mail(to: "ada@example.com", subject: "Probe") do |format|
          format.html { render html: %(<p>Café · naïve</p><p><a href="https://x.test/go" style="background: #db2777; padding: 12px 28px; border-radius: 9px;">Go</a></p>).html_safe, layout: "mailer" }
        end
      end
    end
    mailer.probe.deliver_now
    mail = ActionMailer::Base.deliveries.last
    html = mail.html_part.body.decoded.force_encoding("UTF-8")
    expect(html).to include(%(<a href="https://x.test/go" #{standard}>Go</a>), "Café · naïve")
    expect(html).not_to include("border-radius: 9px")
    # The footer's plain links stay plain, and there is still a text version.
    expect(html).to include("Email settings")
    expect(html.scan(described_class::STYLE).size).to eq(1)
    expect(mail.text_part.body.decoded).to include("Go")
  end

  # A new email draws its button with EmailButton::STYLE (or class="button"),
  # never by hand: a hand-drawn one is how six styles piled up.
  it "is the only button the email views and templates draw" do
    files = Dir[Rails.root.join("app/views/**/*mailer*/**/*.erb"), Rails.root.join("app/views/layouts/mailer*.erb"),
                Rails.root.join("app/views/shared/mailer/**/*.erb"), Rails.root.join("app/services/*templates*.rb"),
                Rails.root.join("app/mailers/**/*.rb")]
    expect(files.size).to be > 10
    hand_drawn = files.flat_map do |file|
      File.read(file).each_line.with_index(1).filter_map do |line, number|
        next unless line.match?(/<a\b|link_to/) && line.match?(/background(-color)?\s*:/) && line.match?(/padding/)

        "#{Pathname(file).relative_path_from(Rails.root)}:#{number}"
      end
    end
    expect(hand_drawn).to be_empty, "Draw an email button with EmailButton::STYLE, not by hand:\n#{hand_drawn.join("\n")}"
  end
end
