//
//  TriggerBuildLogicStore.swift
//  BitriseClient
//
//  Created by 鈴木 俊裕 on 2018/02/05.
//  Copyright © 2018 toshi0383. All rights reserved.
//

import Continuum
import Foundation
import RealmSwift

typealias WorkflowID = String
typealias AppSlug = String

/// LogicStore
///
/// - performs database update
/// - publish states for view
/// - triggers new builds via network
///
/// Let's say it's a fat viewcontroller but is testable.
final class TriggerBuildLogicStore {

    // MARK: Output

    let buildDidTriggerRelay: Constant<Void?>
    let alertMessage: Constant<String>

    // MARK: Private

    private let _buildDidTriggerRelay = Variable<Void?>(value: nil)
    private let _alertMessage = Variable<String>(value: "")

    private var realmObject: BuildTriggerRealm!

    // MARK: LifeCycle

    /// NOTE: Accesses to realm in current thread.
    init(appSlug: String) {

        buildDidTriggerRelay = Constant(variable: _buildDidTriggerRelay)
        alertMessage = Constant(variable: _alertMessage)

        let realm = Realm.getRealm()

        if let obj = realm.object(ofType: BuildTriggerRealm.self, forPrimaryKey: appSlug) {
            realmObject = obj
        } else {
            let gitObject = GitObject.branch("")
            let properties: [String: Any?] = [
                "appSlug": appSlug,
                "gitObjectValue": gitObject.associatedValue,
                "gitObjectType": gitObject.type
            ]
            let b = BuildTriggerRealm(value: properties)
            try! realm.write {
                realm.add(b)
            }
            realmObject = b
        }
    }

    // TODO: Remember the last value
    var workflowID: WorkflowID?

    var workflowIDs: List<String> {
        get {
            return realmObject.workflowIDs
        }
    }

    func appendWorkflowID(_ workflowID: WorkflowID) {
        try! Realm.getRealm().write {
            realmObject.workflowIDs.append(workflowID)
        }
    }

    func removeWorkflowID(at row: Int) {
        try! Realm.getRealm().write {
            realmObject.workflowIDs.remove(at: row)
        }
    }

    var apiToken: String? {
        get {
            return realmObject.apiToken
        }
        set {
            try! Realm.getRealm().write {
                realmObject.apiToken = newValue
            }
        }
    }

    var gitObject: GitObject! {
        get {
            return GitObject(realmObject: realmObject)
        }
        set {
            // skip initial value via continuum
            guard let newValue = newValue else {
                return
            }
            try! Realm.getRealm().write {
                realmObject.gitObjectValue = newValue.associatedValue
                realmObject.gitObjectType = newValue.type
            }
        }
    }

    private func urlRequest() -> URLRequest? {

        guard let token = apiToken else { return nil }
        guard let workflowID = workflowID else { return nil }

        guard let url = URL(string: "https://www.bitrise.io/app/\(realmObject.appSlug)/build/start.json") else {
            return nil
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 5.0)

        let body = BuildTriggerRequest(hook_info: .init(api_token: token),
                                       build_params: gitObject.json + ["workflow_id": workflowID])
        req.httpBody = try! JSONEncoder().encode(body)
        req.httpMethod = "POST"

        return req
    }

    func triggerBuild() {

        guard let req = urlRequest() else {
            alert("ERROR: Could not build request.")
            return
        }

        let task = URLSession.shared.dataTask(with: req) { [weak self] (data, res, err) in

            guard let me = self else { return }

            #if DEBUG
                if let res = res as? HTTPURLResponse {
                    print(res.statusCode)
                    print(res.allHeaderFields)
                }
            #endif

            if let err = err {
                me.alert(err.localizedDescription)
                return
            }

            guard (res as? HTTPURLResponse)?.statusCode == 201 else {
                me.alert("Fail")
                return
            }

            let str: String = {
                if let data = data {
                    return String(data: data, encoding: .utf8) ?? ""
                } else {
                    return ""
                }
            }()

            me._buildDidTriggerRelay.value = ()

            me.alert("Success\n\(str)")
        }

        task.resume()
    }

    private func alert(_ string: String) {
        _alertMessage.value = string
    }
}

typealias JSON = [String: String]
func + (_ lhs: JSON, _ rhs: JSON) -> JSON {
    var r: JSON = [:]
    lhs.forEach { r[$0] = $1 }
    rhs.forEach { r[$0] = $1 }
    return r
}
