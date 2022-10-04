//
//  ExampleStackViewController.swift
//  ExampleStackView
//
//  Created by Görkem Gür on 13.09.2022.
//

import UIKit

class ExampleStackViewController: UIViewController {

    @IBOutlet weak var exampleStackView: UIStackView!
    
    private var mockData = [MockExampleModel]()
    private var mockViews = [MockView]()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        mockData = getRandomModel()
        
        setupUI()

    }
    
    private func setupUI() {
        for i in 0..<mockData.count {
            let mockView = MockView()
            mockView.tag = i
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tappedMockView))
            mockView.addGestureRecognizer(tapGesture)
            mockView.setupView(showBottomLine: mockData[i].index != mockData.last?.index, model: mockData[i])
            mockViews.append(mockView)
        }
        print("Geldi")
        exampleStackView.addArrangedSubviews(mockViews)
    }
    
    @objc func tappedMockView(_ sender: UITapGestureRecognizer) {
         guard let getTag = sender.view?.tag else { return }
        let tappedView = exampleStackView.getTappedView(index: getTag) as? MockView
        let title = tappedView?.getModel()?.title ?? ""
        let description = tappedView?.getModel()?.description ?? ""
        let alert = UIAlertController(title: "Title: \(title)", message: "Description: \(description)\nTapped Index: \(getTag)", preferredStyle: .alert)
        let alertAction = UIAlertAction(title: "OK", style: .default, handler: { _ in
            alert.dismiss(animated: true)
        })
        alert.addAction(alertAction)
        self.present(alert, animated: true)
    }
    

}

struct MockExampleModel {
    var title:String?
    var description:String?
    var index: Int?
}
