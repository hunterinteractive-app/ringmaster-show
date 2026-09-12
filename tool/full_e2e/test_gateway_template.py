"""Gateway budget changes must not change the surrounding CLI configuration."""
import unittest
from configure_capacity import gateway_entrypoint


class GatewayTemplateTests(unittest.TestCase):
    settings={'KONG_NGINX_EVENTS_WORKER_CONNECTIONS':'4096',
              'KONG_NGINX_MAIN_WORKER_RLIMIT_NOFILE':'8192'}

    def test_original_and_previous_templates_upgrade_without_touching_surroundings(self):
        originals=['events {\n    multi_accept on;\n}',
            'worker_rlimit_nofile 4096;\n\nevents {\n    worker_connections 2048;\n    multi_accept on;\n}']
        expected='worker_rlimit_nofile 8192;\n\nevents {\n    worker_connections 4096;\n    multi_accept on;\n}'
        for original in originals:
            before=['sh','-c','unchanged routes and credential placeholder\n'+original+'\nunchanged certificate placeholder']
            after,changed=gateway_entrypoint(before,self.settings)
            self.assertTrue(changed)
            self.assertEqual(after[:2],before[:2])
            self.assertEqual(after[2],before[2].replace(original,expected))
            self.assertEqual(gateway_entrypoint(after,self.settings),(after,False))

    def test_unknown_or_ambiguous_template_is_rejected(self):
        for text in ('events { worker_connections 9000; }',
                     'events {\n    multi_accept on;\n}\nevents {\n    multi_accept on;\n}'):
            with self.assertRaises(RuntimeError):gateway_entrypoint(['sh','-c',text],self.settings)


if __name__=='__main__':unittest.main()
