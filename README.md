# Kubernetes Task Service

Terraform module which deploys task service on Kubernetes.

## Usage

```hcl
module "example" {
  source = "..."

  infrastructure = {
    namespace = "default"
  }

  deployment = {
    timeout: 30                     # in seconds
    execute_strategy:
      type = periodic
      periodic = {
        cron_expression = "*/1 * * * *"        # cron expression
      }
  }

  containers = [
    {
      name = "report"
      image = {
        name = "alpine"
        pull_policy = "IfNotPresent"
      }
      execute = {
        command = [
          "/bin/sh", "-c", "date"
        ]
      }
      resources = {
        requests = {
          cpu = 0.1
          memory = 100              # in megabyte
        }
      }
    }
  ]
}
```

## Examples

- ...
- ...

## Contributing

Please read our [contributing guide](./docs/CONTRIBUTING.md) if you're interested in contributing to Walrus template.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.23.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.23.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_config_map_v1.configs](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_cron_job_v1.periodic](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cron_job_v1) | resource |
| [kubernetes_job_v1.once](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/job_v1) | resource |
| [kubernetes_secret_v1.configs](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [kubernetes_secret_v1.image_registry_credentials](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [kubernetes_service_v1.tasks](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context"></a> [context](#input\_context) | Receive contextual information. When Walrus deploys, Walrus will inject specific contextual information into this field.<br><br>Examples:<pre>context:<br>  project:<br>    name: string<br>    id: string<br>  environment:<br>    name: string<br>    id: string<br>  resource:<br>    name: string<br>    id: string</pre> | `map(any)` | `{}` | no |
| <a name="input_infrastructure"></a> [infrastructure](#input\_infrastructure) | Specify the infrastructure information for deploying.<br><br>Examples:<pre>infrastructure:<br>  namespace: string, optional<br>  gpu_vendor: string, optional</pre> | <pre>object({<br>    namespace  = optional(string)<br>    gpu_vendor = optional(string, "nvidia.com")<br>  })</pre> | `{}` | no |
| <a name="input_deployment"></a> [deployment](#input\_deployment) | Specify the task action, like execution, security and so on.<br><br>Examples:<pre>deployment:<br>  timeout: number, optional<br>  completions: number, optional<br>  parallelism: number, optional<br>  retries: number, optional<br>  cleanup: bool, optional                  # cleanup after 5m<br>  execute_strategy:<br>    type: once/periodic<br>    once: {}<br>    periodic:<br>      cron_expression: string<br>      timezone: string, optional           # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones<br>      suspend: bool, optional<br>      keep_not_finished: bool, optional    # forbids concurrent runs if true<br>  system_controls:<br>  - name: string<br>    value: string</pre> | <pre>object({<br>    timeout     = optional(number)<br>    completions = optional(number)<br>    parallelism = optional(number)<br>    retries     = optional(number, 6)<br>    cleanup     = optional(bool, false)<br>    execute_strategy = optional(object({<br>      type = optional(string, "once")<br>      once = optional(object({}), {})<br>      periodic = optional(object({<br>        cron_expression   = string<br>        timezone          = optional(string)<br>        suspend           = optional(bool, false)<br>        keep_not_finished = optional(bool, false)<br>      }))<br>    }))<br>    system_controls = optional(list(object({<br>      name  = string<br>      value = string<br>    })))<br>  })</pre> | <pre>{<br>  "execute_strategy": {<br>    "cleanup": false,<br>    "once": {},<br>    "type": "once"<br>  },<br>  "retries": 6,<br>  "timeout": 0<br>}</pre> | no |
| <a name="input_credentials"></a> [credentials](#input\_credentials) | Specify the credential items to fetch private data, like an internal image registry.<br><br>Examples:<pre>credentials:<br>- name: string                           # unique<br>  type: image_registry<br>  image_registry: <br>    server: string<br>    username: string<br>    password: string<br>    email: string, optional</pre> | <pre>list(object({<br>    name = string<br>    type = optional(string, "image_registry")<br>    image_registry = optional(object({<br>      server   = string<br>      username = string<br>      password = string<br>      email    = optional(string)<br>    }))<br>  }))</pre> | `[]` | no |
| <a name="input_configs"></a> [configs](#input\_configs) | Specify the configuration items to configure containers, either raw or sensitive data.<br><br>Examples:<pre>configs:<br>- name: string                           # unique<br>  type: data                             # convert to config map<br>  data: <br>    (key: string): string<br>- name: string<br>  type: secret                           # convert to secret<br>  secret:<br>    (key: string): string</pre> | <pre>list(object({<br>    name   = string<br>    type   = optional(string, "data")<br>    data   = optional(map(string))<br>    secret = optional(map(string))<br>  }))</pre> | `[]` | no |
| <a name="input_storages"></a> [storages](#input\_storages) | Specify the storage items to mount containers.<br><br>Examples:<pre>storages:<br>- name: string                           # unique<br>  type: empty                            # convert ot empty_dir volume<br>  empty:<br>    medium: string, optional<br>    size: number, optional               # in megabyte<br>- name: string<br>  type: nas                              # convert to in-tree nfs volume<br>  nas:<br>    read_only: bool, optional<br>    server: string<br>    path: string, optional<br>    username: string, optional<br>    password: string, optional<br>- name: string<br>  type: san                              # convert to in-tree fc or iscsi volume<br>  san:<br>    read_only: bool, optional<br>    fs_type: string, optional<br>    type: fc/iscsi<br>    fc: <br>      lun: number<br>      wwns: list(string)<br>    iscsi<br>      lun: number, optional<br>      portal: string<br>      iqn: string<br>- name: string<br>  type: ephemeral                         # convert to dynamic volume claim template<br>  ephemeral:<br>    class: string, optional<br>    access_mode: string, optional<br>    size: number, optional                # in megabyte<br>- name: string<br>  type: persistent                        # convert to existing volume claim template<br>  persistent:<br>    read_only: bool, optional<br>    name: string                          # the name of persistent volume claim</pre> | <pre>list(object({<br>    name = string<br>    type = optional(string, "empty")<br>    empty = optional(object({<br>      medium = optional(string)<br>      size   = optional(number)<br>    }))<br>    nas = optional(object({<br>      read_only = optional(bool, false)<br>      server    = string<br>      path      = optional(string, "/")<br>      username  = optional(string)<br>      password  = optional(string)<br>    }))<br>    san = optional(object({<br>      read_only = optional(bool, false)<br>      fs_type   = optional(string, "ext4")<br>      type      = string<br>      fc = optional(object({<br>        lun  = optional(number, 0)<br>        wwns = list(string)<br>      }))<br>      iscsi = optional(object({<br>        lun    = optional(number, 0)<br>        portal = string<br>        iqn    = string<br>      }))<br>    }))<br>    ephemeral = optional(object({<br>      class       = optional(string)<br>      access_mode = optional(string, "ReadWriteOnce")<br>      size        = number<br>    }))<br>    persistent = optional(object({<br>      read_only = optional(bool, false)<br>      name      = string<br>    }))<br>  }))</pre> | `[]` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | Specify the container items to deployment.<br><br>Examples:<pre>containers:<br>- name: string                           # unique<br>  profile: init/run<br>  image:<br>    name: string<br>    pull_policy: string, optional<br>  execute:<br>    command: list(string), optional<br>    args: list(string), optional<br>    working_dir: string, optional<br>    as: string, optional                # i.e. non_root, user_id:group:id<br>  resources:<br>    requests:<br>      cpu: number, optional             # in oneCPU, i.e. 0.25, 0.5, 1, 2, 4, 8<br>      memory: number, optional          # in megabyte<br>      gpu: number, optional             # i.e. 0.25, 0.5, 1, 2, 4, 8<br>    limits:<br>      cpu: number, optioanl             # in oneCPU, i.e. 0.25, 0.5, 1, 2, 4, 8<br>      memory: number, optional          # in megabyte<br>      gpu: number, optional             # i.e. 0.25, 0.5, 1, 2, 4, 8<br>  envs:<br>  - name: string, optional              # only work if the config.key is null<br>    type: text/config<br>    text:<br>      content: string<br>    config:<br>      name: string<br>      key: string, optional<br>  mounts:<br>  - path: string                        # unique<br>    read_only: bool, optional<br>    type: config/storage<br>    config:<br>      name: string<br>      key: string, optional<br>      mode: string, optional<br>      disable_changed: bool, optional   # only work if config.key is not null<br>    storage:<br>      name: string<br>      sub_path: string, optional</pre> | <pre>list(object({<br>    name    = string<br>    profile = optional(string, "run")<br>    image = object({<br>      name        = string<br>      pull_policy = optional(string, "IfNotPresent")<br>    })<br>    execute = optional(object({<br>      command     = optional(list(string))<br>      args        = optional(list(string))<br>      working_dir = optional(string)<br>      as          = optional(string)<br>    }))<br>    resources = optional(object({<br>      requests = object({<br>        cpu    = optional(number, 0.1)<br>        memory = optional(number, 64)<br>        gpu    = optional(number, 0)<br>      })<br>      limits = optional(object({<br>        cpu    = optional(number, 0)<br>        memory = optional(number, 0)<br>        gpu    = optional(number, 0)<br>      }))<br>    }))<br>    envs = optional(list(object({<br>      name = optional(string)<br>      type = optional(string, "text")<br>      text = optional(object({<br>        content = string<br>      }))<br>      config = optional(object({<br>        name = string<br>        key  = optional(string)<br>      }))<br>    })))<br>    mounts = optional(list(object({<br>      path      = string<br>      read_only = optional(bool, false)<br>      type      = optional(string, "config")<br>      config = optional(object({<br>        name            = string<br>        key             = optional(string)<br>        mode            = optional(string, "0644")<br>        disable_changed = optional(bool, false)<br>      }))<br>      storage = optional(object({<br>        name     = string<br>        sub_path = optional(string)<br>      }))<br>    })))<br>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_context"></a> [context](#output\_context) | The input context, a map, which is used for orchestration. |
| <a name="output_selector"></a> [selector](#output\_selector) | The selector, a map, which is used for dependencies or collaborations. |
<!-- END_TF_DOCS -->

## License

Copyright (c) 2023 [Seal, Inc.](https://seal.io)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [LICENSE](./LICENSE) file for details.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
