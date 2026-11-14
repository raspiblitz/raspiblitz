#!/usr/bin/python3
# Unit tests for lndPayInvoice in blitz.subscriptions.ip2tor.py (LND REST /v2/router/send).
# Run from this folder: python3 -m unittest test_ip2tor_pay.py  (needs: requests)

import importlib.util
import json
import os
import sys
import types
import unittest
from unittest import mock

import requests

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'home.admin')
sys.path.insert(0, os.path.join(ROOT, 'BlitzPy', 'blitzpy'))

# stub the modules the script imports but the payment path does not use
for name in ('grpc', 'toml', 'config', 'lndlibs', 'lndlibs.lightning_pb2', 'lndlibs.lightning_pb2_grpc'):
    sys.modules.setdefault(name, mock.MagicMock())


def load_script():
    path = os.path.join(ROOT, 'config.scripts', 'blitz.subscriptions.ip2tor.py')
    spec = importlib.util.spec_from_file_location('ip2tor', path)
    module = importlib.util.module_from_spec(spec)
    with mock.patch.object(sys, 'argv', ['ip2tor', 'test']), mock.patch('builtins.print'):
        spec.loader.exec_module(module)
    return module


ip2tor = load_script()
from exceptions import BlitzError  # noqa: E402 (same class the script uses)


def fake_response(lines=(), status=200, iter_error=None):
    response = mock.MagicMock()
    response.status_code = status
    if status >= 400:
        response.raise_for_status.side_effect = requests.exceptions.HTTPError(str(status))

    def iter_lines():
        for line in lines:
            yield line if isinstance(line, bytes) else json.dumps(line).encode()
        if iter_error:
            raise iter_error

    response.iter_lines.side_effect = iter_lines
    return response


class LndPayInvoiceTest(unittest.TestCase):

    def pay(self, post_result=None, post_error=None):
        with mock.patch.object(ip2tor, 'open', mock.mock_open(read_data=b'\x01\x02'), create=True), \
                mock.patch.object(ip2tor.requests, 'post', return_value=post_result,
                                  side_effect=post_error) as post:
            self.post = post
            return ip2tor.lndPayInvoice('lnbc1invoice')

    def assertPaymentFails(self, cause=None, **kwargs):
        with self.assertRaises(BlitzError) as ctx:
            self.pay(**kwargs)
        self.assertEqual(ctx.exception.short, 'payment failed')
        if cause:
            self.assertIn(cause, str(ctx.exception.org.short if isinstance(ctx.exception.org, BlitzError)
                                     else ctx.exception.org))
        return ctx.exception

    def test_success(self):
        payment = self.pay(fake_response([
            {'result': {'status': 'IN_FLIGHT'}},
            b'',  # keepalive / empty line is skipped
            {'result': {'status': 'SUCCEEDED', 'payment_hash': 'ab'}},
        ]))
        self.assertEqual(payment['payment_hash'], 'ab')
        args, kwargs = self.post.call_args
        self.assertEqual(args, ('https://{0}:8080/v2/router/send'.format(ip2tor.LND_IP),))
        self.assertEqual(kwargs['headers'], {'Grpc-Metadata-macaroon': '0102'})
        self.assertEqual(kwargs['json'], {'payment_request': 'lnbc1invoice', 'fee_limit_sat': 1000,
                                          'timeout_seconds': 60})
        self.assertEqual(kwargs['verify'], ip2tor.LND_TLS_PATH)
        self.assertTrue(kwargs['stream'])
        self.assertEqual(kwargs['timeout'], (10, 90))

    def assertPaymentInFlight(self, **kwargs):
        with self.assertRaises(BlitzError) as ctx:
            self.pay(**kwargs)
        self.assertEqual(ctx.exception.short, 'payment in flight')
        self.assertEqual(ctx.exception.details['payment_hash'], 'ab')

    def test_connection_failure(self):
        self.assertPaymentFails('refused', post_error=requests.exceptions.ConnectionError('refused'))

    def test_http_error(self):
        self.assertPaymentFails('500', post_result=fake_response(status=500))

    def test_streamed_error(self):
        self.assertPaymentFails('invoice expired',
                                post_result=fake_response([{'error': {'code': 2, 'message': 'invoice expired'}}]))

    def test_failed_terminal_state(self):
        self.assertPaymentFails('FAILURE_REASON_NO_ROUTE', post_result=fake_response([
            {'result': {'status': 'IN_FLIGHT'}},
            {'result': {'status': 'FAILED', 'failure_reason': 'FAILURE_REASON_NO_ROUTE'}},
        ]))

    def test_empty_stream(self):
        self.assertPaymentFails('payment not completed', post_result=fake_response([b'', b'']))

    def test_stalled_stream_before_update(self):
        # requests raises ConnectionError(ReadTimeoutError) when no bytes arrive within the read timeout
        self.assertPaymentFails('timed out', post_result=fake_response(
            [], iter_error=requests.exceptions.ConnectionError('Read timed out.')))

    def test_stalled_stream_in_flight(self):
        # an HTLC is pending when the stream stalls: it can still settle, so this is not a failure
        self.assertPaymentInFlight(post_result=fake_response(
            [{'result': {'status': 'IN_FLIGHT', 'payment_hash': 'ab'}}],
            iter_error=requests.exceptions.ConnectionError('Read timed out.')))

    def test_stream_ends_in_flight(self):
        self.assertPaymentInFlight(post_result=fake_response(
            [{'result': {'status': 'IN_FLIGHT', 'payment_hash': 'ab'}}]))

    def test_error_after_in_flight(self):
        self.assertPaymentInFlight(post_result=fake_response([
            {'result': {'status': 'IN_FLIGHT', 'payment_hash': 'ab'}},
            {'error': {'code': 14, 'message': 'server shutting down'}},
        ]))


if __name__ == '__main__':
    unittest.main()
