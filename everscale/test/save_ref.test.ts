import { expect } from "chai";
import { afterRun, logContract, deployRefFactory, deployAccount, deriveRef, deployProject as deployProject, deployRefSystem, runOnRefferral, approveProject } from './utils';
import { FactorySource } from "../build/factorySource";

import logger from "mocha-logger"
import { Contract } from "locklift";
import { Account } from "everscale-standalone-client";
// const { setupRelays, setupBridge } = require('./utils/bridge');

describe('Save Refferral', function () {
    this.timeout(10000000);

    describe('RefFactory', function () {
        describe('contructor', function () {
            it('should deploy RefFactory', async function () {
                let refOwnerPair = await locklift.keystore.getSigner("0")
                let refFactoryOwner = await deployAccount(refOwnerPair!, 50);

                let refFactory = await deployRefFactory(refFactoryOwner)
                expect((await refFactory.methods.owner().call()).owner.equals(refFactoryOwner.address)).to.be.true
            })
        })
    })
    describe("RefSystem", function () {
        describe('constructor', function () {
            it('should deploy RefSystem', async () => {
                let refFactoryOwnerPair = await locklift.keystore.getSigner("0")
                let refFactoryOwner = await deployAccount(refFactoryOwnerPair!, 50);
                let refFactory = await deployRefFactory(refFactoryOwner)

                let refOwnerPair = await locklift.keystore.getSigner("1")
                let refSysOwner = await deployAccount(refOwnerPair!, 50);

                let refSystem = await deployRefSystem(refFactoryOwner, refFactory, refSysOwner, 300, 1000);
                expect((await refSystem.methods._approvalFee().call())._approvalFee)
                    .to.be.bignumber.equal(300, 'Wrong Value');
            })
        })

        describe('deployProject', function () {
            let project: Contract<FactorySource["Project"]>;
            let refSystem: Contract<FactorySource["RefSystem"]>;
            let refSysOwner: Account;


            it('should deploy Project uninitialized', async function () {
                let refFactoryOwnerPair = await locklift.keystore.getSigner("0")
                let projectOwnerPair = await locklift.keystore.getSigner("1")
                let refOwnerPair = await locklift.keystore.getSigner("2")

                let refFactoryOwner = await deployAccount(refFactoryOwnerPair!, 50);
                let projectOwner = await deployAccount(projectOwnerPair!, 50, "projectOwner");
                refSysOwner = await deployAccount(refOwnerPair!, 50, "refSysOwner");

                let refFactory = await deployRefFactory(refFactoryOwner)
                refSystem = await deployRefSystem(refFactoryOwner, refFactory, refSysOwner, 300, 1000);
                logContract(refSystem, "RefSystem");

                project = await deployProject(projectOwner, refSystem, 5, 5, 100);
                logContract(project, "Project");

                let { _owner } = await project.methods._owner().call()
                logger.log(_owner, projectOwner.address);
                expect(_owner.equals(projectOwner.address)).to.be.true
                expect((await (await project.methods._isApproved().call())._isApproved).to.be.false;
            })

            it('should be approved by RefSystem', async function () {
                await approveProject(project, refSysOwner, refSystem)
                expect((await (await project.methods._isApproved().call())._isApproved).to.be.true;
            })
        })

    })

    describe("RefSystemUpgradeable", function () {
        it('should be upgradeable by owner')
        it('should have version')
    })

    describe('ProjectUpgradeable', function () {
        it('should be upgradeable by owner')
        it('should have version')
        it('should not be initialized after upgrade')
        it('should be initialized by RefSystem')
    })

    describe('RefInstanceUpgradeable', function () {
        it('should be upgradeable by RefSystem')
        it('should have version')
    })

    describe('AccountUpgradeable', function () {
        it('should be upgradeable by RefSystem')
        it('should have version')
    })

    describe('Project', function () {
        describe('onRefferal()', function () {
            it('should pass on all fees on success', async function () {
                let refFactoryOwnerPair = await locklift.keystore.getSigner("0")
                let refOwnerPair = await locklift.keystore.getSigner("1")
                let projectOwnerPair = await locklift.keystore.getSigner("2")
                let bobPair = await locklift.keystore.getSigner("3")
                let alicePair = await locklift.keystore.getSigner("4")
                let jerryPair = await locklift.keystore.getSigner("5")

                let refFactoryOwner =  await deployAccount(refFactoryOwnerPair!, 50, 'refSysOwner');
                let refSysOwner = await deployAccount(refOwnerPair!, 50, 'refSysOwner');
                let projectOwner = await deployAccount(projectOwnerPair!, 50, 'projectOwner');
                let bob = await deployAccount(bobPair!, 50, 'bob');
                let alice = await deployAccount(alicePair!, 50, 'alice');
                let jerry = await deployAccount(jerryPair!, 50, 'jerry');
                
                let refFactory = await deployRefFactory(refFactoryOwner)
                let refSystem = await deployRefSystem(refFactoryOwner, refFactory, refSysOwner, 300, 1000);
                let project = await deployProject(projectOwner, refSystem, 5, 5, 100);
                await approveProject(project, refSysOwner, refSystem)

                let bobBalance = Number((await locklift.provider.getBalance(bob.address)))
                let aliceBalance = Number(await locklift.provider.getBalance(alice.address))
                let refSystemBalance = Number(await locklift.provider.getBalance(refSystem.address))
                let projectBalance = Number(await locklift.provider.getBalance(project.address))

                let reward = 10;

                await runOnRefferral(projectOwner, project, bob.address, alice.address, reward);

                let new_bobBalance = Number(await locklift.provider.getBalance(bob.address))
                let new_aliceBalance = Number(await locklift.provider.getBalance(alice.address))
                let new_refSystemBalance = Number(await locklift.provider.getBalance(refSystem.address))
                let new_projectBalance = Number(await locklift.provider.getBalance(project.address))

                // expect(new_projectBalance).to.equal(projectBalance+Number(locklift.utils.convertCrystal(reward*5/100, 'nano')))
                // expect(new_refSystemBalance).to.equal(refSystemBalance+Number(locklift.utils.convertCrystal(reward*30/100, 'nano')))

                expect(new_aliceBalance - aliceBalance).to.be.greaterThanOrEqual(Number(locklift.utils.fromNano(reward * 5 / 100)) * 0.95)
                expect(new_bobBalance - bobBalance).to.be.greaterThanOrEqual(Number(locklift.utils.fromNano(reward * 60 / 100)) * 0.95)

                let refInstance = await deriveRef(refSystem, alice.address)

                await logContract(refInstance, "RefInstance")
                expect((await refInstance.methods.lastRef_().call()).lastRef_.equals(bob.address)).to.be.true

                // Should Update Parent
                await runOnRefferral(projectOwner, project, jerry.address, alice.address, reward);
                expect((await refInstance.methods.lastRef_().call()).lastRef_.equals(jerry.address)).to.be.true

            })
        })

    })


})