/**
 * Shared HTTPS POST with retries for all LLM providers, and the provider-neutral
 * error type the agent loop understands. Each provider maps its own error format
 * onto LlmError.errorType values: authentication_error, permission_error,
 * not_found_error, rate_limit_error, overloaded_error, billing_error,
 * invalid_request_error, api_error, network_error, invalid_response.
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

const MAX_RETRIES = 3;
const CONNECT_TIMEOUT_MS = 15000;
// A step normally answers within ~20 s; a stalled connection is retried instead of blocking the task for minutes.
const READ_TIMEOUT_MS = 90000;

export class LlmError extends Error {
  status: number;
  errorType: string;
  retryable: boolean;

  constructor(status: number, errorType: string, message: string, retryable: boolean) {
    super(message);
    this.name = 'LlmError';
    this.status = status;
    this.errorType = errorType;
    this.retryable = retryable;
  }
}

export interface HttpResponse {
  status: number;
  body: string;
  retryAfter?: string;
}

/** Turns a provider's raw response into a result, or throws LlmError (retryable or not). */
export type ResponseHandler<T> = (resp: HttpResponse) => T;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

export function retryDelayMs(attempt: number, retryAfterHeader: string | undefined): number {
  if (retryAfterHeader) {
    const seconds = parseFloat(retryAfterHeader);
    if (!isNaN(seconds) && seconds >= 0) {
      return Math.min(seconds * 1000, 60000);
    }
  }
  return Math.min(1000 * Math.pow(2, attempt), 16000);
}

async function postOnce(url: string, headers: Record<string, string>, body: string): Promise<HttpResponse> {
  const request = http.createHttp();
  try {
    const resp = await request.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    });
    const respHeaders = resp.header as Record<string, string>;
    return {
      status: resp.responseCode,
      body: typeof resp.result === 'string' ? resp.result as string : '',
      retryAfter: respHeaders ? respHeaders['retry-after'] : undefined
    };
  } finally {
    request.destroy();
  }
}

/** POSTs JSON and hands the response to `handle`; retries retryable failures with backoff. */
export async function postWithRetry<T>(url: string, headers: Record<string, string>, body: string,
  handle: ResponseHandler<T>): Promise<T> {
  let lastError: LlmError = new LlmError(0, 'unknown', 'request not sent', true);
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    let retryAfter: string | undefined = undefined;
    try {
      const resp = await postOnce(url, headers, body);
      retryAfter = resp.retryAfter;
      return handle(resp);
    } catch (e) {
      if (e instanceof LlmError) {
        lastError = e as LlmError;
      } else {
        const err = e as BusinessError;
        // network-level failure (DNS, connect, timeout): retryable
        lastError = new LlmError(0, 'network_error', `Network error ${err.code}: ${err.message}`, true);
      }
    }
    if (!lastError.retryable || attempt === MAX_RETRIES) {
      break;
    }
    await sleep(retryDelayMs(attempt, retryAfter));
  }
  throw lastError;
}

/** Common HTTP-status -> errorType mapping used when a provider gives no better signal. */
export function errorTypeForStatus(status: number): string {
  if (status === 401) {
    return 'authentication_error';
  }
  if (status === 403) {
    return 'permission_error';
  }
  if (status === 404) {
    return 'not_found_error';
  }
  if (status === 429) {
    return 'rate_limit_error';
  }
  if (status === 503 || status === 529) {
    return 'overloaded_error';
  }
  if (status >= 500) {
    return 'api_error';
  }
  return 'invalid_request_error';
}

export function isRetryableStatus(status: number): boolean {
  return status === 429 || status >= 500;
}
