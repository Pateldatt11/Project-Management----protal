const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';

function sendJson(res, status, body) {
  res.status(status).setHeader('Content-Type', 'application/json');
  return res.end(JSON.stringify(body));
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return sendJson(res, 405, { error: 'Method not allowed' });
  }

  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    return sendJson(res, 500, { error: 'Chat service is not configured' });
  }

  const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  if (!body || !Array.isArray(body.messages) || typeof body.model !== 'string') {
    return sendJson(res, 400, { error: 'Invalid chat request' });
  }

  try {
    const upstream = await fetch(GROQ_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
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
    return sendJson(res, 502, { error: 'Unable to reach chat service' });
  }
};
