# Once Task Example

Start once task by root moudle.

```bash
# setup infra
$ tf apply -auto-approve \
  -target=kubernetes_namespace_v1.example

# create service
$ tf apply -auto-approve \
  -target=module.non_parallel

$ tf apply -auto-approve \
  -target=module.parallel

$ tf apply -auto-approve \
  -target=module.queue
```

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

| Name | Source | Version |
|------|--------|---------|
| <a name="module_non_parallel"></a> [non\_parallel](#module\_non\_parallel) | ../.. | n/a |
| <a name="module_parallel"></a> [parallel](#module\_parallel) | ../.. | n/a |
| <a name="module_queue"></a> [queue](#module\_queue) | ../.. | n/a |

## Resources

| Name | Type |
|------|------|
| [kubernetes_namespace_v1.example](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_non_parallel_context"></a> [non\_parallel\_context](#output\_non\_parallel\_context) | n/a |
| <a name="output_non_parallel_refer"></a> [non\_parallel\_refer](#output\_non\_parallel\_refer) | n/a |
| <a name="output_parallel_context"></a> [parallel\_context](#output\_parallel\_context) | n/a |
| <a name="output_parallel_refer"></a> [parallel\_refer](#output\_parallel\_refer) | n/a |
| <a name="output_queue_context"></a> [queue\_context](#output\_queue\_context) | n/a |
| <a name="output_queue_refer"></a> [queue\_refer](#output\_queue\_refer) | n/a |
<!-- END_TF_DOCS -->
