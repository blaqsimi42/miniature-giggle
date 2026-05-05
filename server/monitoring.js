// Basic monitoring helper for webhook failures and alerts.
// In production, wire this to PagerDuty, Slack, or an observability platform.

function alertWebhookFailure(details) {
  // Placeholder: emit structured log and, if configured, call an alerting webhook.
  console.error('[ALERT] Webhook failure:', JSON.stringify(details));
}

module.exports = { alertWebhookFailure };
