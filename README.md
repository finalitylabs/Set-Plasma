# Set-Plasma
[Set](https://docs.google.com/document/d/1aQdLnBNAWYIqDoYLjBPcyh3Pjo0rcQMZtjcrOzIYVek/edit?usp=sharing) protocol extension of [Plasma](https://plasma.io/). A state-channels, plasma, and verification game approach to scaling complex layer2 applications.

[Theory - WIP](https://docs.google.com/document/d/15LdH-YL3syBHdHlwCfUHou6XFvg5lXBKtrAFp5bG1Pc/edit?usp=sharing)

This implementation aims to achieve scalable
  - Ether payments
  - ERC20 payments
  - NFT exchanges
  - NFT simple market
  - NFT discovery (communal process)
  - complex state-channel logic
  - verification game channels
  
  
### Hub-and-spoke / Operator

The consesus mechanism chosen for this layer2 plasma chain is PoA. We provide safe exits and a client library to allow anyone to easliy reboot a corrupt plasma chain or to simply compete with better fees.

### Accounts

Set-Plasma chains use an account model similar to Ethereum. This is in contrast to the UTXO model used by Plasma-MVP and more similar to Plasma-Cash+Debit. 

#### State Objects

State is represented in Bitcoin and Plasma-MVP as a collection of unspent transaction outputs. This limits computation to that of a stack based scripting language. While many things can be achieved in such a model, this implementation attempts to produce state in a account model. We produce "state objects" that represent the storage and ownership of arbitratry state.

#### Ownership

Creating a layer2 account model plasma chain comes with questions about who owns the state objects at all times as it is necessary for the exit mechanics to know who has the right to move state from the child chain to the parent chain. See [this](https://ethresear.ch/t/why-smart-contracts-are-not-feasible-on-plasma) eth research post for more details. 

### Honest Exits

### Byzantine Exits

### Fees and Bonds


