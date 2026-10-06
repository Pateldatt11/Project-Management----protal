const ONESIGNAL_URL = 'https://onesignal.com/api/v1/notifications';

function sendJson(res, status, body) {
  res.status(status).setHeader('Content-Type', 'application/json');
  return res.end(JSON.stringify(body));
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return sendJson(res, 405, { error: 'Method not allowed' });
  }

  const apiKey = process.env.ONESIGNAL_REST_API_KEY;
  const appId = process.env.ONESIGNAL_APP_ID;
  if (!apiKey || !appId) {
    return sendJson(res, 500, { error: 'Notification service is not configured' });
  }

  const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return sendJson(res, 400, { error: 'Invalid notification request' });
  }

  try {
    const upstream = await fetch(ONESIGNAL_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        Authorization: `Key ${apiKey}`,
      },
      body: JSON.stringify({ ...body, app_id: appId }),
    });

    const responseText = await upstream.text();
    let responseBody;
    try {
      responseBody = JSON.parse(responseText);
    } catch (_) {
      responseBody = { error: responseText || 'Invalid upstream response' };
    }

    return sendJson(res, upstream.status, responseBody);
  } catch (error) {
    return sendJson(res, 502, { error: 'Unable to reach notification service' });
  }
};
