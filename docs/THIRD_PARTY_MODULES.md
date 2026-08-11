# Third-party proxy modules

The files under `Resources/ThirdPartyProxyModules/` are project-owned module
definitions used by the App's default domestic-mirror subscription path. Their
executable scripts are built from `ThirdParty/WlocScripts/src/` and checked in
under the versioned `ThirdParty/WlocScripts/dist/v1/` directory.

The direct GitHub Raw variants are stored under
`ThirdParty/WlocScripts/modules/direct/`. The Settings switch selects which
module URL the App copies:

- enabled by default: `gh-proxy.org` in front of GitHub Raw;
- disabled: GitHub Raw directly.

The App appends the module version as a query parameter, such as `?v=1.0.0`.
Increment this value whenever an existing module path changes so proxy clients
do not reuse a previously cached subscription body.

| Module file | Client |
|---|---|
| `wloc.module` | Shadowrocket |
| `wloc.sgmodule` | Surge and Egern |
| `wloc.conf` | Quantumult X |
| `wloc.lpx` | Loon |
| `wloc.stoverride` | Stash |

Egern reuses the Surge module. Stash imports `.stoverride` directly.

Both script entry points are owned by this repository:

- `wloc.js` patches Apple WLOC response bodies;
- `wloc-settings.js` implements `/wloc-settings/save` and
  `/wloc-settings/version`.

The generated scripts target ES2017 and avoid hard dependencies on `BigInt`,
optional chaining, nullish coalescing, `globalThis`, `URLSearchParams`, and
`Object.fromEntries`. This keeps them usable by older proxy-client releases
that still implement the established module syntax, binary response body,
`$done`, and persistent-storage APIs.

Already-installed legacy modules that point to another repository are not
silently migrated because their remote script URL is outside this project's
control. Those users must re-import the project-owned module before using the
versioned protocol and motion setting.

Current bundled module SHA-256 values:

```text
263f3eae0ec4ef19d03eefa58f28e6545cccbc6a2d32c5e1d3493ba207ca7605  wloc.conf
c0755a9edb2a1686190d12d156e9aa53693e15721efc4a29f9a06c2bf3115a5f  wloc.lpx
06a426e4f37828d18b80abea04a8ade4fa7f93817cb1e37928c52da3e46f693a  wloc.module
f6b9fc51c4d3c4fca837ff896dbe544f99604d9646f05841bad82bfdfdf5c4fa  wloc.sgmodule
100e569e6ca3183f7da15fbb38ddb5cd91178488c0d9774acabc2721fa85a58c  wloc.stoverride
```

The project acknowledges [Yu9191/wloc](https://github.com/Yu9191/wloc) as a
reference for earlier WLOC implementation ideas. That acknowledgement is not
an executable dependency or subscription source.
