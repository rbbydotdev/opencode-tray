import Foundation
import HelperProtocol

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperServiceConstants.machServiceName)
listener.delegate = delegate
listener.resume()

dispatchMain()
