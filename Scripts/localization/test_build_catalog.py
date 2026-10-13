import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_catalog


class PlaceholderTests(unittest.TestCase):
    def test_flags_width_and_precision_preserve_argument_types(self):
        self.assertEqual(
            build_catalog.placeholder_types('%.1f %+.2f %08lld %-10@ %.3g'),
            [(1, 'f'), (2, 'f'), (3, 'lld'), (4, '@'), (5, 'g')],
        )

    def test_escaped_percent_does_not_consume_arguments(self):
        self.assertEqual(build_catalog.placeholder_types('%%f %%@ %%%.1f'), [(1, 'f')])

    def assert_catalog(self, entry, error=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'source.json').write_text(json.dumps({'test': entry}))
            with patch.object(build_catalog, 'HERE', root), patch.object(build_catalog, 'ROOT', root):
                if error:
                    with self.assertRaisesRegex(AssertionError, error):
                        build_catalog.catalog()
                else:
                    self.assertIn('test', build_catalog.catalog()['strings'])

    def test_positional_reordering_is_accepted(self):
        self.assert_catalog({'en': '%@ %.1f', 'zh-Hans': '%2$+.2f %1$@'})

    def test_wrong_type_at_argument_position_is_rejected(self):
        self.assert_catalog({'en': '%@ %.1f', 'zh-Hans': '%2$@ %1$.1f'}, 'Placeholder mismatch')

    def test_missing_precision_argument_is_rejected(self):
        self.assert_catalog({'en': '%.1f kg', 'zh-Hans': '千克'}, 'Placeholder mismatch')

    def test_wrong_precision_argument_type_is_rejected(self):
        self.assert_catalog({'en': '%+.2f kg', 'zh-Hans': '%lld 千克'}, 'Placeholder mismatch')

    def test_plural_missing_precision_argument_is_rejected(self):
        self.assert_catalog(
            {'en': '%.1f items', 'zh-Hans': '%.1f 项', 'enOne': 'one item'},
            'Plural mismatch',
        )


if __name__ == '__main__':
    unittest.main()
