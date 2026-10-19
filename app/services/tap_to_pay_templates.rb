# frozen_string_literal: true

# The words Apple requires at Tap to Pay on iPhone's launch (Apple's
# publishing review 6.1 and 6.3): a launch email and a push, both from
# Apple's Marketing Guide copy (US, Sept 2026), with CocoScout in Apple's
# [partner] blanks. Apple allows no other words for these, so edit them only
# from a newer Apple guide. Seeded as ContentTemplates (the PlatformTemplates
# pattern) and sent by TapToPayLaunch.
class TapToPayTemplates
  DISCLAIMERS = <<~HTML.squish
    <p style="color:#6b7280;font-size:11px;line-height:1.5;margin-top:28px">Tap to Pay on iPhone requires a supported payment app and the latest version of iOS. Update to the latest version by going to Settings &gt; General &gt; Software Update. Some contactless cards may not be accepted by your payment app. Transaction limits may apply. Tap to Pay on iPhone is not available in all markets. For Tap to Pay on iPhone countries and regions, see https://developer.apple.com/tap-to-pay/regions/.</p>
    <p style="color:#6b7280;font-size:11px;line-height:1.5">*Encrypted card numbers are temporarily stored on iPhone only for transactions made in Store and Forward mode.</p>
    <p style="color:#6b7280;font-size:11px;line-height:1.5">The Contactless Indicator mark, consisting of four graduating arcs, is a trademark owned by and used with permission of EMVCo, LLC.</p>
    <p style="color:#6b7280;font-size:11px;line-height:1.5">Apple Pay is a service provided by Apple Payments Services LLC, a subsidiary of Apple Inc. Neither Apple Inc. nor Apple Payments Services LLC is a bank. Any card used in Apple Pay is offered by the card issuer.</p>
  HTML

  TEMPLATES = [
    { key: "tap_to_pay_launch", name: "Tap to Pay on iPhone: launch email", channel: "email",
      subject: "Tap to Pay on iPhone",
      body: <<~HTML.squish + DISCLAIMERS,
        <h1 style="font-size:28px;line-height:1.15;margin:0 0 8px">Tap to Pay on iPhone</h1>
        <p style="font-size:18px;color:#4b5563;margin:0 0 16px">Accept contactless payments right on your iPhone.</p>
        <p>Tap to Pay on iPhone is now available with CocoScout. That means you can accept all types of in-person, contactless payments—from physical debit and credit cards to Apple Pay and other digital wallets. Right on your iPhone.</p>
        <p><a href="{{settings_url}}">Get started</a></p>
        <p><img src="{{hero_image_url}}" alt="" width="520" style="width:100%;max-width:520px;height:auto"></p>
        <h2 style="font-size:20px;margin:24px 0 4px">Expand where you do business.</h2>
        <p>Reach more customers, accept payments on the go, and explore new setups, like line busting. All you need is your iPhone.</p>
        <h2 style="font-size:20px;margin:24px 0 4px">Streamline checkout with no additional hardware.</h2>
        <p>Tap to Pay on iPhone is easy to set up and use. No card readers or terminals required.</p>
        <h2 style="font-size:20px;margin:24px 0 4px">Privacy and security of iPhone built in.</h2>
        <p>Apple doesn't store card numbers on Apple servers, helping protect your business and customer data.*</p>
        <h2 style="font-size:20px;margin:24px 0 4px">Get started in a few steps.</h2>
        <p>1. Download the CocoScout app.<br>2. Complete sign-up information.<br>3. Accept in-person, contactless payments—right on iPhone.</p>
      HTML
      variables: [ { "name" => "settings_url", "description" => "Tap to Pay on iPhone in the CocoScout app" },
                   { "name" => "hero_image_url", "description" => "Apple's Tap to Pay on iPhone image" } ] },
    { key: "tap_to_pay_launch_message", name: "Tap to Pay on iPhone: launch message and push", channel: "message",
      subject: "Accept in-person payments with Tap to Pay on iPhone.",
      body: %(<p>Accept in-person, contactless payments right on your iPhone, from physical debit and credit cards to Apple Pay and other digital wallets. Terms apply.</p><p><a href="{{settings_url}}">Get started</a></p>),
      push_body: "Accept in-person, contactless payments right on your iPhone, from physical debit and credit cards to Apple Pay and other digital wallets. Terms apply.",
      variables: [ { "name" => "settings_url", "description" => "Tap to Pay on iPhone in the CocoScout app" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "ticketing", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.push_body = spec[:push_body] if spec[:push_body]
      template.save!
    end
  end
end
