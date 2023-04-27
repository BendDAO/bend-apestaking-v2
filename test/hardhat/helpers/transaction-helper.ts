/* eslint-disable node/no-extraneous-import */
import { TransactionReceipt } from "@ethersproject/abstract-provider";
import { utils } from "ethers";
import { Result } from "ethers/lib/utils";

export const parseEvents = (
  receipt: TransactionReceipt,
  abiInterface: utils.Interface
): { [eventName: string]: Result } => {
  const txEvents: { [eventName: string]: Result } = {};
  for (const log of receipt.logs) {
    for (const event of Object.values(abiInterface.events)) {
      const topichash = log.topics[0].toLowerCase();
      if (topichash === abiInterface.getEventTopic(event.name)) {
        txEvents[event.name] = abiInterface.decodeEventLog(event, log.data, log.topics);
      }
    }
  }
  return txEvents;
};
