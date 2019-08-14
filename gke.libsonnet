local kube = import 'kube.libsonnet';

{
  ManagedCertificate(name): kube._Object('networking.gke.io/v1beta1', 'ManagedCertificate', name) {
    local cert = self,

    assert std.length(self.spec.domains) == 1 : 'domains should have 1 item',

    domains_:: [],

    spec: {
      domains: cert.domains_,
    },
  },
}
