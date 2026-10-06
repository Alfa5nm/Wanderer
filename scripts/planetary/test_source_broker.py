import io
import json
from pathlib import Path
import tempfile
import unittest

from source_broker import SourceBroker, validate_request


class BrokerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.time = 1000000
        self.calls = 0
        self.failure = False
        self.body = dict(features=[dict(id='published-test', assets={'dtm': {'href': 'fixture'}})])
        self.broker = SourceBroker(self.directory.name, ttl=10, fetch=self.fetch, now=lambda: self.time)
        self.bounds = [137.43, -4.60, 137.45, -4.58]

    def fetch(self, url, timeout):
        self.calls += 1
        if self.failure:
            raise OSError('service outage')
        return io.BytesIO(json.dumps(self.body).encode())

    def test_cold_then_warm_avoids_network(self):
        first = self.broker.discover(self.bounds)
        self.assertEqual(len(first), 2)  # Each instrument is queried separately.
        self.assertEqual(self.broker.discover(self.bounds), first)
        self.assertEqual(self.calls, 2)
        self.assertEqual(self.broker.metrics['hits'], 2)

    def test_expiry_refreshes(self):
        self.broker.discover(self.bounds)
        self.time += 11
        self.broker.discover(self.bounds)
        self.assertEqual(self.calls, 4)

    def test_service_failure_preserves_stale_catalog(self):
        first = self.broker.discover(self.bounds)
        self.time += 11
        self.failure = True
        self.assertEqual(self.broker.discover(self.bounds), first)
        self.assertEqual(self.broker.metrics['stale_hits'], 2)

    def test_stale_catalog_eventually_expires(self):
        self.broker.discover(self.bounds)
        self.time += 31 * 86400
        self.failure = True
        self.assertEqual(self.broker.discover(self.bounds), [])

    def test_corrupt_cache_refetches(self):
        self.broker.discover(self.bounds)
        for path in Path(self.directory.name).glob('*.json'):
            path.write_text('broken-json')
        self.assertEqual(len(self.broker.discover(self.bounds)), 2)
        self.assertEqual(self.calls, 4)

    def test_invalid_cache_timestamp_refetches(self):
        self.broker.discover(self.bounds)
        for path in Path(self.directory.name).glob('*.json'):
            value = json.loads(path.read_text())
            value['cached_at'] = 'not-a-timestamp'
            path.write_text(json.dumps(value))
        self.assertEqual(len(self.broker.discover(self.bounds)), 2)
        self.assertEqual(self.calls, 4)

    def test_unknown_provider_and_invalid_geography_rejected(self):
        job = dict(bounds=self.bounds, kind='elevation', size=512)
        validate_request(job)
        for patch in [dict(bounds=[0, -91, 1, 0]), dict(bounds=[0, 0, float('nan'), 1]),
                      dict(bounds=[170, 0, -170, 1]), dict(size=4096), dict(provider='unimplemented')]:
            with self.assertRaises(ValueError):
                validate_request(dict(job, **patch))

    def test_group_cache_has_size_bound(self):
        self.broker.discover(self.bounds)
        self.broker.prune(0)
        self.assertEqual(list(Path(self.directory.name).glob('*')), [])

    def test_unsupported_collection_rejected(self):
        with self.assertRaises(ValueError):
            self.broker.discover(self.bounds, ['fictional-elevation'])


if __name__ == '__main__':
    unittest.main()
