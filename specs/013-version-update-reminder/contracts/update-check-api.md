# HTTP Contract: Update Check

## `GET /api/v1/update-check`

Returns the latest validated stable release for the fixed public ContainerGui GitHub repository compared with the running GUI version.

### Request

- Method: `GET`
- Body: none
- Query parameters: none
- Authentication: none; localhost same-origin policy applies

### Success response

- Status: `200 OK`
- Content-Type: `application/json; charset=utf-8`

```json
{
  "currentVersion": "2.17.0",
  "latestVersion": "2.18.0",
  "updateAvailable": true,
  "releaseURL": "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0",
  "publishedAt": "2026-09-01T03:00:00Z"
}
```

`publishedAt` may be absent when GitHub omits it. `releaseURL` is present only after fixed-host and path validation.

### Failure response

- Status: `502 Bad Gateway`
- Content-Type: `application/problem+json; charset=utf-8`
- Code: `UPDATE_CHECK_UNAVAILABLE`
- Retryable: `true`

The safe response does not include the upstream body, network exception, token, or arbitrary URL.

### Safety and availability

- The route never mutates containers, images, application files, or release state.
- Upstream redirects are not followed.
- Upstream response body is limited to 128 KiB and the request to 5 seconds.
- Only the fixed GitHub API repository endpoint may be requested.
- Only a validated public stable release page under the fixed repository may be returned.
