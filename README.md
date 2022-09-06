# adc-broker-deploy

## Install the ADC Broker application
Run `./adc_broker.sh install`.
Run `./adc_broker.sh build`.

## Start the ADC Broker application
Run `./adc_broker.sh start` (a `--detached` option is available).
Wait for the angular build to be finished.
The application is now operational.

## Certificates
To regenerate all nginx certificates. First, you must delete them.
Run `rm nginx/ssl/adc-broker-nginx-key*`
They are recreated during the build.

### Website
The website is accessible at the address http://localhost (for the moment it is not accessible outside the VM).
An administrator admin@mail.com is created by default with the default password admin (it need to be changed).

#### Publisher interface
The REST message publishing interface is available at the address http://localhost/api/publish.

#### Subscriber interface
The AMQP message receiving interface is available at the address amqps://username:password@localhost:5771/queue_path.
The username in this address correspond to the first part of a subscriber mail (before the @). Only subscribers users have access to the broker.

## Send a message
In a first time we need to get a token.
Run `curl --location --request POST 'http://localhost/api/token/' --form 'username="<username>"' --form 'password="<password>"'`.
This will return a connection token for the user.

Then we can send a message
Run `curl --location --request POST 'http://localhost/api/publish/' --header 'Authorization: Token <myToken>' --form 'policy_id="<publisher policy id>"' --form 'message="<message>"'`.
The policy_id can be obtained in the publisher page.

## Receive a message
To receive AMQP messages, a test client is available.
Run `export PYTHONPATH=$(pwd)/git/adc-broker-backend/`.
Run `cd git/adc-broker-backend/backend/amqp/test_clients`.
Run `python3 ReceiveAmqps.py -u amqps://<username>:<password>@localhost:5771/ -a <queue path>`.
The username in this address correspond to the first part of a subscriber mail (before the @).

## Stop the ADC Broker application
Run `./adc_broker.sh stop` (a `--purge` option is available to reset all the data).
