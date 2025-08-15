# Decentralized Insurance Pool
## Peer-to-Peer Insurance Smart Contract

A decentralized insurance system built on the Stacks blockchain that enables community-driven claims processing and automated risk assessment. This smart contract facilitates peer-to-peer insurance pools where participants can stake funds, obtain coverage, and collectively validate claims through a consensus-based validation system.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Contract Functions](#contract-functions)
- [Usage Examples](#usage-examples)
- [Security Features](#security-features)
- [Testing](#testing)
- [Deployment](#deployment)
- [Contributing](#contributing)
- [License](#license)

## Overview

The Peer-to-Peer Insurance contract eliminates traditional insurance intermediaries by creating community-managed insurance pools. Participants stake STX tokens to create or join insurance pools, pay premiums based on risk assessments, and participate in a decentralized claims validation process.

### Key Benefits

- **Decentralized Governance**: No central authority controls claims processing
- **Transparent Operations**: All transactions and decisions are recorded on-chain
- **Community-Driven Validation**: Claims are validated by staked validators
- **Automated Risk Assessment**: Built-in risk scoring for premium calculations
- **Cost Efficient**: Reduced overhead compared to traditional insurance

## Features

### Core Functionality

- **Insurance Pool Creation**: Users can create specialized insurance pools for different risk categories
- **Policy Management**: Automated policy creation and premium collection
- **Claims Processing**: Decentralized claims submission and validation system
- **Validator Network**: Stake-weighted validator system for claims assessment
- **Risk Assessment**: Automated risk scoring and premium calculation

### Supported Insurance Types

- Health Insurance (`health`)
- Property Insurance (`property`)
- Life Insurance (`life`)
- Auto Insurance (`auto`)
- Travel Insurance (`travel`)

### Claim Types

- Medical Claims (`medical`)
- Property Damage (`damage`)
- Theft Claims (`theft`)
- Accident Claims (`accident`)
- Death Claims (`death`)

## Architecture

### Smart Contract Structure

```
├── Constants & Error Codes
├── Data Variables
├── Data Maps
│   ├── insurance-pools
│   ├── pool-policies
│   ├── insurance-claims
│   ├── claim-validators
│   └── validators
├── Input Validation Functions
├── Pool Management Functions
├── Validator System Functions
├── Claims Processing Functions
└── Read-Only Functions
```

### Key Constants

- **MIN_POOL_STAKE**: 1,000 STX minimum stake to join a pool
- **MIN_VALIDATOR_STAKE**: 500 STX minimum stake to become a validator
- **MAX_POOL_SIZE**: 100 maximum participants per pool
- **CLAIM_VALIDATION_PERIOD**: ~1 week for claim validation
- **MIN_VALIDATORS_REQUIRED**: 3 minimum validators per claim
- **VALIDATOR_CONSENSUS_THRESHOLD**: 66% agreement needed for claim approval

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) v0.31.1 or later
- [Node.js](https://nodejs.org/) v14+ (for testing utilities)
- Stacks wallet for testnet/mainnet deployment

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-org/p2p-insurance-contract
cd p2p-insurance-contract
```

2. Install Clarinet:
```bash
curl -L https://github.com/hirosystems/clarinet/releases/download/v0.31.1/clarinet-linux-x64.tar.gz | tar xz
sudo mv clarinet /usr/local/bin/
```

3. Initialize the project:
```bash
clarinet new p2p-insurance
cd p2p-insurance
```

4. Copy the contract to the contracts directory:
```bash
cp peer-to-peer-insurance.clar contracts/
```

### Quick Start

1. **Check contract syntax**:
```bash
clarinet check
```

2. **Run tests**:
```bash
clarinet test
```

3. **Launch console for interaction**:
```bash
clarinet console
```

## Contract Functions

### Pool Management

#### `create-insurance-pool`
Creates a new insurance pool with specified parameters.

**Parameters:**
- `pool-name`: Pool identifier (validated for length)
- `pool-type`: Insurance type (must be from predefined types)
- `max-coverage-per-claim`: Maximum payout per claim
- `base-premium-rate`: Base premium rate (0-50%)

#### `join-insurance-pool`
Allows users to join an existing insurance pool.

**Parameters:**
- `pool-id`: Target pool identifier
- `stake-amount`: STX amount to stake (minimum 1,000 STX)
- `coverage-amount`: Desired coverage amount

### Validator System

#### `register-as-validator`
Register as a claims validator with specialized expertise.

**Parameters:**
- `stake-amount`: STX to stake as validator (minimum 500 STX)
- `specialization`: Area of expertise (health, property, auto, life, general)

#### `validate-claim`
Validate a submitted insurance claim.

**Parameters:**
- `claim-id`: Claim to validate
- `approve`: Validation decision (true/false)
- `stake-amount`: STX amount to stake on decision

### Claims Processing

#### `submit-claim`
Submit an insurance claim for validation.

**Parameters:**
- `pool-id`: Insurance pool ID
- `claim-amount`: Requested payout amount
- `claim-type`: Type of claim (medical, damage, theft, etc.)
- `description`: Claim description (max 256 chars)
- `evidence-hash`: Hash of supporting evidence

### Premium Management

#### `pay-premium`
Pay monthly premium for an active policy.

**Parameters:**
- `policy-id`: Policy identifier

## Usage Examples

### Creating an Insurance Pool

```clarity
;; Create a health insurance pool
(contract-call? .peer-to-peer-insurance create-insurance-pool 
  "Health Coverage Pool"
  "health"
  u50000000  ;; 50 STX max coverage
  u1000      ;; 10% base premium rate
)
```

### Joining a Pool

```clarity
;; Join pool with 10 STX stake for 25 STX coverage
(contract-call? .peer-to-peer-insurance join-insurance-pool 
  u1         ;; pool-id
  u10000000  ;; 10 STX stake
  u25000000  ;; 25 STX coverage
)
```

### Submitting a Claim

```clarity
;; Submit a medical claim
(contract-call? .peer-to-peer-insurance submit-claim
  u1                    ;; pool-id
  u5000000             ;; 5 STX claim amount
  "medical"            ;; claim type
  "Emergency surgery"  ;; description
  "abc123hash"         ;; evidence hash
)
```

### Validating a Claim

```clarity
;; Approve a claim as validator
(contract-call? .peer-to-peer-insurance validate-claim
  u1        ;; claim-id
  true      ;; approve
  u1000000  ;; 1 STX validation stake
)
```

## Security Features

### Input Validation
- All string inputs validated against predefined constants
- Comprehensive bounds checking for numeric parameters
- Protection against malicious input data

### Access Control
- Role-based permissions for validators and pool participants
- Stake-weighted validation system
- Anti-spam measures through minimum stake requirements

### Economic Security
- Validators must stake STX on their decisions
- Consensus threshold prevents single-point manipulation
- Automatic slashing for incorrect validations (future enhancement)

### Data Integrity
- Immutable claim records
- Cryptographic evidence hashing
- Transparent validation process

## Testing

### Unit Tests

Run comprehensive test suite:
```bash
clarinet test
```

### Integration Tests

Test complete workflows:
```bash
clarinet test --coverage
```

### Manual Testing

Use Clarinet console for interactive testing:
```bash
clarinet console
>> (contract-call? .peer-to-peer-insurance get-insurance-stats)
```

## Deployment

### Testnet Deployment

1. Configure Clarinet.toml for testnet:
```toml
[network]
name = "testnet"
```

2. Deploy contract:
```bash
clarinet deployments apply --network testnet
```

### Mainnet Deployment

1. Configure for mainnet:
```toml
[network]
name = "mainnet"
```

2. Deploy with proper security review:
```bash
clarinet deployments apply --network mainnet
```

## API Reference

### Read-Only Functions

- `get-pool-details(pool-id)`: Retrieve pool information
- `get-policy-details(policy-id)`: Get policy details
- `get-claim-details(claim-id)`: Fetch claim information
- `get-validator-info(validator)`: Validator statistics
- `get-insurance-stats()`: Contract-wide statistics
- `get-pool-health(pool-id)`: Pool health metrics

### Constants Reference

```clarity
MIN-POOL-STAKE: 1,000,000 microSTX
MIN-VALIDATOR-STAKE: 500,000 microSTX
MAX-POOL-SIZE: 100 participants
CLAIM-VALIDATION-PERIOD: 1,008 blocks (~1 week)
MIN-VALIDATORS-REQUIRED: 3
VALIDATOR-CONSENSUS-THRESHOLD: 66%
```

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 300 | ERR-NOT-AUTHORIZED | Insufficient permissions |
| 301 | ERR-NOT-FOUND | Resource not found |
| 302 | ERR-INSUFFICIENT-BALANCE | Insufficient STX balance |
| 303 | ERR-INVALID-AMOUNT | Invalid amount specified |
| 304 | ERR-POOL-FULL | Pool at maximum capacity |
| 305 | ERR-CLAIM-EXPIRED | Claim validation period expired |
| 306 | ERR-CLAIM-ALREADY-PROCESSED | Claim already validated |
| 307 | ERR-INSUFFICIENT-VALIDATORS | Not enough validators |
| 308 | ERR-ALREADY-VALIDATED | Validator already voted |
| 309 | ERR-INVALID-RISK-SCORE | Invalid risk assessment |
| 310 | ERR-PAYOUT-FAILED | Claim payout failed |
| 311 | ERR-INVALID-INPUT | Invalid input parameters |

## Roadmap

### Phase 1 (Current)
- ✅ Basic pool creation and management
- ✅ Claims submission and validation
- ✅ Validator registration and staking
- ✅ Premium calculation and collection

### Phase 2 (Planned)
- ⏳ Advanced risk assessment models
- ⏳ Automated premium adjustments
- ⏳ Validator reputation system
- ⏳ Cross-pool reinsurance

### Phase 3 (Future)
- ⏳ Oracle integration for external data
- ⏳ Governance token for protocol decisions
- ⏳ Layer 2 scaling solutions
- ⏳ Mobile app integration

## Contributing

We welcome contributions to improve the peer-to-peer insurance system!

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

### Contribution Guidelines

- Follow Clarity best practices
- Maintain backward compatibility
- Include comprehensive tests
- Update documentation
- Follow semantic versioning

### Code Style

- Use descriptive function and variable names
- Include comprehensive comments
- Follow Clarity naming conventions
- Maintain consistent indentation

## Security

### Reporting Vulnerabilities

Please report security vulnerabilities to [security@yourorg.com](mailto:security@yourorg.com). Do not open public issues for security concerns.

### Security Best Practices

- Regular security audits
- Formal verification of critical functions
- Bug bounty program
- Multi-signature deployment process

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

### Community

- Discord: [Join our community](https://discord.gg/yourserver)
- Telegram: [Development discussions](https://t.me/yourchannel)
- Forum: [Technical discussions](https://forum.yoursite.com)

### Documentation

- [Technical Documentation](https://docs.yoursite.com)
- [API Reference](https://api-docs.yoursite.com)
- [Video Tutorials](https://youtube.com/yourchannel)

### Professional Support

For enterprise support and custom development:
- Email: [enterprise@yourorg.com](mailto:enterprise@yourorg.com)
- Schedule consultation: [Book a call](https://calendly.com/yourteam)

---

**Built with ❤️ for the decentralized insurance ecosystem**