// Cherry picked and slightly modified "Fork" of
// https://github.com/bitnami-labs/kube-libsonnet

{
  // Returns array of values from given object.  Does not include hidden fields.
  objectValues(o):: [
    o[field]
    for field in std.objectFields(o)
  ],

  // Returns array of [key, value] pairs from given object.  Does not include hidden fields.
  objectItems(o):: [
    [k, o[k]]
    for k in std.objectFields(o)
  ],

  // Replace all occurrences of `_` with `-`.
  hyphenate(s):: std.join('-', std.split(s, '_')),

  // Convert {foo: {a: b}} to [{name: foo, a: b}]
  mapToNamedList(o):: [
    { name: $.hyphenate(n) } + o[n]
    for n in std.objectFields(o)
  ],

  _Object(apiVersion, kind, name):: {
    local this = self,

    apiVersion: apiVersion,
    kind: kind,
    metadata: {
      name: name,
      labels: {
        app: std.join('-', std.split(this.metadata.name, ':')),
      },
      annotations: {},
    },
  },

  ClusterRole(name): $.Role(name) {
    kind: 'ClusterRole',
  },

  ClusterRoleBinding(name): $.RoleBinding(name) {
    kind: 'ClusterRoleBinding',
  },

  ConfigMap(name): $._Object('v1', 'ConfigMap', name) {
    data: {},
  },

  ConfigMapRef(configmap, key): {
    assert std.objectHas(configmap.data, key) : '%s not in configmap.data' % [key],

    configMapKeyRef: {
      name: configmap.metadata.name,
      key: key,
    },
  },

  ConfigMapVolume(configmap): {
    configMap: {
      name: configmap.metadata.name,
    },
  },

  Container(name): {
    name: name,
    image: error 'container image value required',

    imagePullPolicy:
      if std.endsWith(self.image, ':latest') then
        'Always'
      else
        'IfNotPresent',

    envList(map):: [
      if std.type(map[x]) == 'object' then
        { name: x, valueFrom: map[x] }
      else
        { name: x, value: map[x] }

      for x in std.objectFields(map)
    ],

    env_:: {},
    env: self.envList(self.env_),

    args_:: {},
    args: [
      '--%s=%s' % kv
      for kv in $.objectItems(self.args_)
    ],

    ports_:: {},
    ports: $.mapToNamedList(self.ports_),

    volumeMounts_:: {},
    volumeMounts: $.mapToNamedList(self.volumeMounts_),
  },

  DaemonSet(name): $._Object('apps/v1', 'DaemonSet', name) {
    local daemon_set = self,

    spec: {
      updateStrategy: {
        type: 'RollingUpdate',
        rollingUpdate: {
          maxUnavailable: 1,
        },
      },

      template: {
        metadata: {
          labels: daemon_set.metadata.labels,
          annotations: {},
        },
        spec: $.PodSpec,
      },

      selector: {
        matchLabels: daemon_set.spec.template.metadata.labels,
      },
    },
  },

  Deployment(name): $._Object('apps/v1', 'Deployment', name) {
    local deployment = self,

    spec: {
      assert self.replicas >= 1,

      replicas: 1,

      selector: {
        matchLabels: deployment.spec.template.metadata.labels,
      },

      template: {
        spec: $.PodSpec,
        metadata: {
          labels: deployment.metadata.labels,
          annotations: {},
        },
      },

      // NB: Upstream default is 0
      minReadySeconds: 30,
    },
  },

  Group(name): {
    kind: 'Group',
    name: name,
    apiGroup: 'rbac.authorization.k8s.io',
  },

  Ingress(name): $._Object('networking.k8s.io/v1beta1', 'Ingress', name) {
    assert std.length(rel_paths) == 0 : 'paths must be absolute: ' + rel_paths,

    local rel_paths = [
      p.path
      for r in self.spec.rules
      for p in r.http.paths
      if !std.startsWith(p.path, '/')
    ],
  },

  IngressRule(host, service): {
    local this = self,

    path:: '/',

    host: host,
    http: {
      paths: [
        {
          backend: service.name_port,
          path: this.path,
        },
      ],
    },
  },

  IngressTLS(hosts): {
    assert std.length(self.hosts) > 0 : 'must have at least one host',

    secretName_:: hosts[0],

    secretName: std.join('-', [self.secretName_, 'cert']),
    hosts: hosts,
  },

  IngressTLSAnnotations: {
    challenge:: 'http01',
    issuer:: 'letsencrypt-prod',

    'certmanager.k8s.io/acme-challenge-type': self.challenge,
    'certmanager.k8s.io/cluster-issuer': self.issuer,
  },

  List(): {
    apiVersion: 'v1',
    kind: 'List',
    items_:: {},
    items: $.objectValues(self.items_),
  },

  Namespace(name): $._Object('v1', 'Namespace', name) {
  },

  PodSpec: {
    assert std.length(self.containers) > 0 : 'must have at least one container',

    local container_names = std.objectFields(self.containers_),

    containers_:: {},
    default_container::
      if std.length(container_names) > 1 then
        'default'
      else
        container_names[0],

    local container_names_ordered =
      [self.default_container] +
      [
        n
        for n in container_names
        if n != self.default_container
      ],

    containers: [
      { name: $.hyphenate(name) } + self.containers_[name]
      for name in container_names_ordered
      if self.containers_[name] != null
    ],

    // Note initContainers are inherently ordered, and using this
    // named object will lose that ordering.  If order matters, then
    // manipulate `initContainers` directly (perhaps
    // appending/prepending to `super.initContainers` to mix+match
    // both approaches)
    initContainers_:: {},
    initContainers: [
      { name: $.hyphenate(name) } + self.initContainers_[name]
      for name in std.objectFields(self.initContainers_)
      if self.initContainers_[name] != null
    ],

    volumes_:: {},
    volumes: $.mapToNamedList(self.volumes_),

    terminationGracePeriodSeconds: 30,
  },

  Role(name): $._Object('rbac.authorization.k8s.io/v1', 'Role', name) {
    rules: [],
  },

  RoleBinding(name): $._Object('rbac.authorization.k8s.io/v1', 'RoleBinding', name) {
    local role_binding = self,

    subjects_:: [],
    subjects: [{
      kind: o.kind,
      name: o.metadata.name,
      [if role_binding.kind == 'RoleBinding' then 'namespace']: o.metadata.namespace,
    } for o in self.subjects_],

    roleRef_:: error 'roleRef is required',
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: role_binding.roleRef_.kind,
      name: role_binding.roleRef_.metadata.name,
    },
  },

  Secret(name): $._Object('v1', 'Secret', name) {
    local secret = self,

    type: 'Opaque',
    data_:: {},
    data: {
      [k]: std.base64(secret.data_[k])
      for k in std.objectFields(secret.data_)
    },
  },

  SecretKeyRef(secret, key): {
    assert std.objectHas(secret.data, key) : '%s not in secret.data' % [key],

    secretKeyRef: {
      name: secret.metadata.name,
      key: key,
    },
  },

  SecretVolume(secret): {
    secret: {
      secretName: secret.metadata.name,
    },
  },

  Service(name): $._Object('v1', 'Service', name) {
    local service = self,

    target_pod:: error 'service target_pod required',
    port:: service.target_pod.spec.containers[0].ports[0].containerPort,

    // Useful in Ingress rules
    name_port:: {
      serviceName: service.metadata.name,
      servicePort: service.spec.ports[0].port,
    },

    spec: {
      selector: service.target_pod.metadata.labels,
      ports: [
        {
          port: service.port,
          targetPort: service.port,
        },
      ],
      type: 'ClusterIP',
    },
  },

  ServiceAccount(name): $._Object('v1', 'ServiceAccount', name) {
  },

  User(name, namespace=null): {
    kind: 'User',
    apiGroup: 'rbac.authorization.k8s.io',
    metadata: {
      name: name,
      [if namespace != null then 'namespace']: namespace,
    },
  },
}
