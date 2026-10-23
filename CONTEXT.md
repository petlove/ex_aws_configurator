# ExAwsConfigurator: domain glossary

Vocabulary used by the code, the docs and the architecture reviews. Terms are the ones
the modules already use; keep new code and docs on them.

## Resources

- **Topic**: an SNS topic declared under the `topics` key. `%ExAwsConfigurator.Topic{}`
  carries its name, naming parts (`prefix`, `environment`, `separator`), `region`,
  attributes and its **Account**. `Topic.full_name/1` and `Topic.arn/1` are pure
  functions of the struct.
- **Queue**: an SQS queue declared under the `queues` key. `%ExAwsConfigurator.Queue{}`
  carries the same naming parts, its options, attributes, its **Account** and the list of
  **Topics** it subscribes to. `Queue.full_name/1`, `Queue.arn/1` and `Queue.policy/1`
  are pure; `Queue.url/1` also reads the SQS endpoint from the ExAws config.
- **Dead letter queue (DLQ)**: the queue that receives the messages a **Queue** failed to
  process `max_receive_count` times. It is a **Queue** derived by
  `Queue.dead_letter_queue/1`: same account, region and naming parts, name plus
  `dead_letter_queue_suffix` (`.fifo` kept at the end), no policies, no topics.
  `Queue.redrive_policy/1` links the queue to it. The SQS adapter ensures the DLQ before
  the queue when `dead_letter_queue: true`, and stops if the DLQ fails.
- **Subscription**: the link between a **Queue** and one of its **Topics**, created by
  `SQS.subscribe/2`. Optionally sets raw message delivery.

## Accounts

- **Account**: an AWS account known to the configurator, `%ExAwsConfigurator.Account{}`
  with `name`, `id` and `region`.
- **Default account**: the one built from the global `account_id` and `region` keys,
  named `:default`. Every **Queue** belongs to it.
- **External account**: any account declared under the `accounts` key whose id differs
  from the default one. A **Topic** that references it (`account: :name`) is an
  **external topic**: its ARN is computed, the queue policy allows it as a source, but
  the setup never creates it and the subscribe call may be refused by its owner
  (`on_unauthorized` decides whether that fails the setup or only warns).
- **Raw ARN topic**: a **Topic** declared with `arn:`; name composition is skipped and
  the account and region come from the ARN itself.

## Configuration

- **Application env**: the `:ex_aws_configurator` keys in `config.exs`. Scalars accept
  `{:system, "ENV_VAR"}`.
- **Config**: `ExAwsConfigurator.Config`, the only module that reads the application
  env. It builds complete structs one at a time (`get_account/1`, `get_topic/1`,
  `get_queue/1`) or all at once.
- **Resolved configuration**: the `%ExAwsConfigurator.Config{accounts, topics, queues}`
  returned by `Config.load/0`: every struct built and every rule validated before any
  call to AWS. `setup/0` works from it.

## Adapters

- **SNS adapter** (`ExAwsConfigurator.SNS`) and **SQS adapter**
  (`ExAwsConfigurator.SQS`): the only modules that call AWS through ExAws. Their
  functions take a struct (the real interface) or the atom that names it in the
  configuration (a one-line convenience that fetches the struct from **Config**).
- **Ensure** (create-or-update): what the adapters do for a resource: look it up, update
  its mutable attributes when it exists, create it otherwise. Never deletes.
- **Setup**: `ExAwsConfigurator.setup/0`, three phases over the **resolved
  configuration**: topics, queues (with their DLQs), subscriptions. Idempotent.

## Test backend

- **floci**: the local SQS/SNS backend the suite talks to (port 4566), shared by every
  test and kept between runs. Factories mark resource names with a per-run id.
- **HttpStub**: the ExAws http client used in tests; forwards to floci and simulates
  what it lacks (name validation, 404 for missing topics, 403 from the external account).
