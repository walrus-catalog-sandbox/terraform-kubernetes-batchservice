# Kubernetes Container Task

Terraform module which deploys container task on Kubernetes.

## Usage

```hcl
module "example" {
  source = "..."

  infrastructure = {
    namespace = "default"
  }

  task = {
    type = periodic
    timeout: 30                              # in seconds
    periodic = {
      cron_expression = "*/1 * * * *"        # cron expression
    }
  }

  containers = [
    {
      image = "alpine"
      execute = {
        command = [
          "/bin/sh", "-c", "date"
        ]
      }
      resources = {
        cpu = 0.1
        memory = 100                         # in megabyte
      }
    }
  ]
}
```

## Examples

- [Once](./examples/once)
- [Periodic](./examples/periodic)

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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_config_map_v1.ephemeral_files](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_cron_job_v1.task](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cron_job_v1) | resource |
| [kubernetes_job_v1.task](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/job_v1) | resource |
| [kubernetes_service_v1.tasks](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |
| [terraform_data.replacement](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context"></a> [context](#input\_context) | Receive contextual information. When Walrus deploys, Walrus will inject specific contextual information into this field.<br><br>Examples:<pre>context:<br>  project:<br>    name: string<br>    id: string<br>  environment:<br>    name: string<br>    id: string<br>  resource:<br>    name: string<br>    id: string</pre> | `map(any)` | `{}` | no |
| <a name="input_infrastructure"></a> [infrastructure](#input\_infrastructure) | Specify the infrastructure information for deploying.<br><br>Examples:<pre>infrastructure:<br>  namespace: string, optional<br>  gpu_vendor: string, optional</pre> | <pre>object({<br>    namespace  = optional(string)<br>    gpu_vendor = optional(string, "nvidia.com")<br>  })</pre> | `{}` | no |
| <a name="input_task"></a> [task](#input\_task) | Specify the task action, like execution, security and so on.<br><br>Examples:<pre>task:<br>  mode: once/periodic<br>  periodic:<br>    cron_expression: string<br>    timezone: string, optional           # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones<br>    suspend: bool, optional<br>    keep_unfinished: bool, optional      # when set to true, if the previous task has not been completed, the new task will not be launched even when the scheduling time arrives<br>  timeout: number, optional<br>  completions: number, optional<br>  parallelism: number, optional<br>  retries: number, optional<br>  cleanup_finished: bool, optional       # cleanup the finished task after 5m<br>  keep_failed_process: bool, optional    # when set to true, the failed process will not be restarted<br>  fs_group: number, optional<br>  sysctls:<br>  - name: string<br>    value: string</pre> | <pre>object({<br>    mode = optional(string, "once")<br>    periodic = optional(object({<br>      cron_expression = string<br>      timezone        = optional(string)<br>      suspend         = optional(bool, false)<br>      keep_unfinished = optional(bool, false)<br>    }))<br>    timeout             = optional(number, 300)<br>    completions         = optional(number)<br>    parallelism         = optional(number)<br>    retries             = optional(number, 6)<br>    cleanup_finished    = optional(bool, false)<br>    keep_failed_process = optional(bool, true)<br>    fs_group            = optional(number)<br>    sysctls = optional(list(object({<br>      name  = string<br>      value = string<br>    })))<br>  })</pre> | <pre>{<br>  "cleanup_finished": false,<br>  "keep_failed_process": true,<br>  "mode": "once",<br>  "retries": 6,<br>  "timeout": 300<br>}</pre> | no |
| <a name="input_containers"></a> [containers](#input\_containers) | Specify the container items to deploy.<br><br>Examples:<pre>containers:<br>- profile: init/run<br>  image: string<br>  execute:<br>    working_dir: string, optional<br>    command: list(string), optional<br>    args: list(string), optional<br>    readonly_rootfs: bool, optional<br>    as_user: number, optional<br>    as_group: number, optional<br>  resources:<br>    cpu: number, optional               # in oneCPU, i.e. 0.25, 0.5, 1, 2, 4<br>    memory: number, optional            # in megabyte<br>    gpu: number, optional               # in oneGPU, i.e. 1, 2, 4<br>  envs:<br>  - name: string<br>    value: string, optional             # accpet changed and restart<br>    value_refer:                        # donot accpet changed<br>      schema: string<br>      params: map(any)<br>  files:<br>  - path: string<br>    mode: string, optional<br>    content: string, optional           # accpet changed but not restart<br>    content_refer:                      # donot accpet changed<br>      schema: string<br>      params: map(any)<br>  mounts:<br>  - path: string<br>    readonly: bool, optional<br>    subpath: string, optional<br>    volume: string, optional            # shared between containers if named, otherwise exclusively by this container<br>    volume_refer:<br>      schema: string<br>      params: map(any)<br>  checks:<br>  - type: execute/tcp/grpc/http/https<br>    delay: number, optional<br>    interval: number, optional<br>    timeout: number, optional<br>    retries: number, optional<br>    teardown: bool, optional<br>    execute:<br>      command: list(string)<br>    tcp:<br>      port: number<br>    grpc:<br>      port: number<br>      service: string, optional<br>    http:<br>      port: number<br>      headers: map(string), optional<br>      path: string, optional<br>    https:<br>      port: number<br>      headers: map(string), optional<br>      path: string, optional</pre> | <pre>list(object({<br>    profile = optional(string, "run")<br>    image   = string<br>    execute = optional(object({<br>      working_dir     = optional(string)<br>      command         = optional(list(string))<br>      args            = optional(list(string))<br>      readonly_rootfs = optional(bool, false)<br>      as_user         = optional(number)<br>      as_group        = optional(number)<br>    }))<br>    resources = optional(object({<br>      cpu    = optional(number, 0.25)<br>      memory = optional(number, 256)<br>      gpu    = optional(number)<br>    }))<br>    envs = optional(list(object({<br>      name  = string<br>      value = optional(string)<br>      value_refer = optional(object({<br>        schema = string<br>        params = map(any)<br>      }))<br>    })))<br>    files = optional(list(object({<br>      path    = string<br>      mode    = optional(string, "0644")<br>      content = optional(string)<br>      content_refer = optional(object({<br>        schema = string<br>        params = map(any)<br>      }))<br>    })))<br>    mounts = optional(list(object({<br>      path     = string<br>      readonly = optional(bool, false)<br>      subpath  = optional(string)<br>      volume   = optional(string)<br>      volume_refer = optional(object({<br>        schema = string<br>        params = map(any)<br>      }))<br>    })))<br>    checks = optional(list(object({<br>      type     = string<br>      delay    = optional(number, 0)<br>      interval = optional(number, 10)<br>      timeout  = optional(number, 1)<br>      retries  = optional(number, 1)<br>      teardown = optional(bool, false)<br>      execute = optional(object({<br>        command = list(string)<br>      }))<br>      tcp = optional(object({<br>        port = number<br>      }))<br>      grpc = optional(object({<br>        port    = number<br>        service = optional(string)<br>      }))<br>      http = optional(object({<br>        port    = number<br>        headers = optional(map(string))<br>        path    = optional(string, "/")<br>      }))<br>      https = optional(object({<br>        port    = number<br>        headers = optional(map(string))<br>        path    = optional(string, "/")<br>      }))<br>    })))<br>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_context"></a> [context](#output\_context) | The input context, a map, which is used for orchestration. |
| <a name="output_refer"></a> [refer](#output\_refer) | The refer, a map, including hosts, ports and account, which is used for dependencies or collaborations. |
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
