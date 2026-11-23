// Passkeys in the browser (sign-in plan phase 4): the server sends WebAuthn
// options as JSON with base64url strings (SignIn::Passkeys); the browser
// wants ArrayBuffers, and its answer goes back as JSON. Browsers that have
// PublicKeyCredential.parse…FromJSON and toJSON do this themselves; the rest
// get it done here.

export function passkeysSupported() {
  return typeof window.PublicKeyCredential === "function" && !!navigator.credentials
}

// Does this browser offer passkeys in an email field's autofill?
export async function autofillSupported() {
  if (!passkeysSupported() || typeof PublicKeyCredential.isConditionalMediationAvailable !== "function") return false
  try {
    return await PublicKeyCredential.isConditionalMediationAvailable()
  } catch {
    return false
  }
}

function toBuffer(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=")
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0)).buffer
}

function fromBuffer(buffer) {
  let text = ""
  new Uint8Array(buffer).forEach((byte) => { text += String.fromCharCode(byte) })
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

export function creationOptions(json) {
  if (typeof PublicKeyCredential.parseCreationOptionsFromJSON === "function") {
    return PublicKeyCredential.parseCreationOptionsFromJSON(json)
  }
  return {
    ...json,
    challenge: toBuffer(json.challenge),
    user: { ...json.user, id: toBuffer(json.user.id) },
    excludeCredentials: (json.excludeCredentials || []).map((c) => ({ ...c, id: toBuffer(c.id) }))
  }
}

export function requestOptions(json) {
  if (typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function") {
    return PublicKeyCredential.parseRequestOptionsFromJSON(json)
  }
  return {
    ...json,
    challenge: toBuffer(json.challenge),
    allowCredentials: (json.allowCredentials || []).map((c) => ({ ...c, id: toBuffer(c.id) }))
  }
}

// The browser's answer, as the JSON the server reads.
export function credentialJSON(credential) {
  if (typeof credential.toJSON === "function") {
    try {
      return credential.toJSON()
    } catch {
      // Some password-manager extensions hand back an object whose toJSON throws.
    }
  }
  const response = credential.response
  const json = {
    id: credential.id,
    rawId: fromBuffer(credential.rawId),
    type: credential.type,
    authenticatorAttachment: credential.authenticatorAttachment || undefined,
    clientExtensionResults: credential.getClientExtensionResults ? credential.getClientExtensionResults() : {},
    response: { clientDataJSON: fromBuffer(response.clientDataJSON) }
  }
  if (response.attestationObject) {
    json.response.attestationObject = fromBuffer(response.attestationObject)
    json.response.transports = typeof response.getTransports === "function" ? response.getTransports() : []
  } else {
    json.response.authenticatorData = fromBuffer(response.authenticatorData)
    json.response.signature = fromBuffer(response.signature)
    json.response.userHandle = response.userHandle ? fromBuffer(response.userHandle) : null
  }
  return json
}

export async function postJSON(url, body = {}) {
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token || "" },
    body: JSON.stringify(body)
  })
  let data = {}
  try { data = await response.json() } catch { data = {} }
  return { ok: response.ok, data }
}

export async function getJSON(url) {
  const response = await fetch(url, { credentials: "same-origin", headers: { Accept: "application/json" } })
  return response.ok ? response.json() : null
}
