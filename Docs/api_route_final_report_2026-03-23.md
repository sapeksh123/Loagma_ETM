# Final API Route Report (2026-03-23)

Base URL: https://loagma-etm.onrender.com/api
Primary evidence sources:
- Docs/api_audit_curl_2026-03-23_14-03-26.md
- Docs/api_audit_curl_2026-03-23_14-03-26.json
- Focused chat timeout run (3 attempts each, valid thread/message + actor headers)

Legend:
- PASS = expected success status.
- VALIDATION_FAIL = expected rejection (validation/business/invalid id context).
- FAIL = unexpected 5xx or timeout.
- UNTESTED = blocked by prerequisites or not safely executable in this pass.

## Chat Timeout Evidence (Target Endpoints)

All 3 endpoints below timed out in all 3 attempts using:
- thread_id = f965046a-7eb4-4096-896f-21407e59c73c
- message_id = 00ef3364-a9f4-47ab-b937-11ddacd295ac
- headers: X-User-Id=U029, X-User-Role=admin, Content-Type=application/json

| Endpoint | Attempt 1 | Attempt 2 | Attempt 3 | Verdict |
|---|---|---|---|---|
| POST /chat/threads/{id}/messages | TIMEOUT 15.269s | TIMEOUT 15.026s | TIMEOUT 15.054s | FAIL |
| POST /chat/threads/{id}/typing | TIMEOUT 15.058s | TIMEOUT 15.028s | TIMEOUT 15.027s | FAIL |
| POST /chat/threads/{id}/receipts | TIMEOUT 15.034s | TIMEOUT 15.040s | TIMEOUT 15.037s | FAIL |

## Route-by-Route Final Matrix (server/routes/api.php)

| Method | Route | Category | HTTP/Observed | Frontend Match | Notes |
|---|---|---|---|---|---|
| GET | /health | PASS | 200 | none | API reachable |
| GET | /db-test | PASS | 200 | none | DB reachable |
| GET | /users | PASS | 200 | auth_service/chat_service/employees_screen | Working |
| GET | /users/by-contact/{contactNumber} | PASS | 200 | auth_service | Working |
| GET | /roles | PASS | 200 | not observed | Working |
| GET | /departments | PASS | 200 | not observed | Working |
| GET | /tasks | PASS | 200 | task_service | Working |
| POST | /tasks | VALIDATION_FAIL | 422 | task_service | Validation rejection observed |
| GET | /tasks/{id} | VALIDATION_FAIL | 404 | task_service | Missing-id case exercised |
| PUT | /tasks/{id} | VALIDATION_FAIL | 404 | task_service | Missing-id case exercised |
| DELETE | /tasks/{id} | VALIDATION_FAIL | 404 | task_service | Missing-id case exercised |
| PATCH | /tasks/{id}/status | FAIL | 500 | task_service | Returned 500 with body: status field required |
| GET | /notes | PASS | 200 | note_service | Working |
| POST | /notes | VALIDATION_FAIL | 422 | note_service | Validation rejection observed |
| GET | /notes/me | PASS | 200 | note_service | Working |
| PUT | /notes/me | VALIDATION_FAIL | 422 | note_service | Validation rejection observed |
| GET | /notes/{id} | VALIDATION_FAIL | 404 | note_service | Missing-id case exercised |
| PUT | /notes/{id} | VALIDATION_FAIL | 404 | note_service | Missing-id case exercised |
| DELETE | /notes/{id} | VALIDATION_FAIL | 404 | note_service | Missing-id case exercised |
| GET | /attendance/today | PASS | 200 | attendance_service | Working |
| GET | /attendance/overview | PASS | 200 | attendance_service | Working |
| POST | /attendance/punch-in | VALIDATION_FAIL | 422 | attendance_service | Validation rejection observed |
| POST | /attendance/punch-out | VALIDATION_FAIL | 422 | attendance_service | Validation rejection observed |
| POST | /attendance/break/start | VALIDATION_FAIL | 422 | attendance_service | Validation rejection observed |
| POST | /attendance/break/end | FAIL | 500 | attendance_service | Returned 500 with body: user id required |
| GET | /dashboard/summary | PASS | 200 | dashboard_service | Working |
| GET | /notifications | PASS | 200 | notification_service | Working |
| POST | /notifications | VALIDATION_FAIL | 422 | notification_service | Validation rejection observed |
| PATCH | /notifications/{id}/read | UNTESTED | no id | notification_service | No notification id available in run |
| POST | /chat/realtime/auth | VALIDATION_FAIL | 422 | chat_service/chat_realtime_client | Validation rejection in matrix run |
| GET | /chat/threads | PASS | 200 | chat_service | Working |
| POST | /chat/threads/direct | VALIDATION_FAIL | 422 | chat_service | Validation rejection in matrix run |
| POST | /chat/threads/broadcast | VALIDATION_FAIL | 422 | not observed | Validation rejection in matrix run |
| GET | /chat/threads/{id}/messages | UNTESTED | blocked in matrix | chat_service | Covered in focused run context only |
| POST | /chat/threads/{id}/messages | FAIL | TIMEOUT x3 | chat_service | Confirmed bottleneck/timeout behavior |
| POST | /chat/threads/{id}/receipts | FAIL | TIMEOUT x3 | chat_service | Confirmed bottleneck/timeout behavior |
| POST | /chat/threads/{id}/read | UNTESTED | not executed | not observed (uses receipts) | Not covered this pass |
| POST | /chat/threads/{id}/messages/{messageId}/delivered | UNTESTED | not executed | not observed (uses receipts) | Not covered this pass |
| POST | /chat/threads/{id}/messages/{messageId}/seen | UNTESTED | not executed | not observed (uses receipts) | Not covered this pass |
| GET | /chat/threads/{id}/messages/{messageId}/reactions | UNTESTED | not executed | not observed | Not covered this pass |
| POST | /chat/threads/{id}/messages/{messageId}/reactions | UNTESTED | not executed | not observed | Not covered this pass |
| DELETE | /chat/threads/{id}/messages/{messageId}/reactions | UNTESTED | not executed | not observed | Not covered this pass |
| POST | /chat/threads/{id}/typing | FAIL | TIMEOUT x3 | chat_service | Confirmed bottleneck/timeout behavior |
| POST | /chat/presence | UNTESTED | not executed | chat_service | Not covered this pass |

## Pinpointed Bottleneck Signal

Because GET /chat/threads is healthy (200, low latency) while all three chat write endpoints time out consistently with valid thread/message and actor headers, the bottleneck is likely in chat write-path internals after middleware resolution (DB transaction/lock, write-related query path, or event/broadcast path), not in global connectivity.

## Frontend Alignment Notes

- Production API default is enabled in client config: client/lib/services/api_config.dart (useProduction default true).
- Frontend chat consumers for failing endpoints are present in chat_service.dart and controller/repository layers.
- Impacted user-visible operations: send message, typing indicator updates, and read/delivery receipt sync.
